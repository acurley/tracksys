class CreatePatronDeliverablesProcessor < ApplicationProcessor

  require 'rubygems'
  require 'RMagick'
  require 'digest/md5'

  subscribes_to :create_patron_deliverables, {:ack=>'client', 'activemq.prefetchSize' => 1}
  publishes_to :delete_unit_copy_for_deliverable_generation

  # Message can have these keys:
  # * pid - pid of the source image file
  # * source - full path to the source image file (master TIFF) to be
  #   processed
  # * mode - "dl", "dl-archive", "patron" or "both"
  # * format - "jpeg" or "tiff" (only applies when mode is "patron" or "both";
  #   defaults to "jpeg")
  # * unit_id (only applies when mode is "patron" or "both")
  # * actual_resolution - resolution of master file (only applies when mode is
  #   "patron" or "both")
  # * desired_resolution - resolution requested by customer for deliverables
  #   (only applies when mode is "patron" or "both"; defaults to highest
  #   possible)
  # * last - If the master file is the last one for a unit, then this processor
  #   will send a message to the archive processor to archive the unit.
  # * remove_watermark - This option, set at the unit level, allows staff to
  #   to disable the inclusion of a watermark for the entire unit if the 
  #   deliverable format is JPEG.
  #
  # Watermark Additions -
  # The following are n required and will only be used if format == 'jpeg'.
  # * call_number - If the item gets a watermark, this value will be added to the notice
  # * title - If the item gets a watermark, this value will be added to the notice.
  # * location - If the item gets a watermark, this value will be added to the notice.
  # * personal_item - If this is true, the watermark doesn't get written at all
  #  
  # Most of these keys are optional, because there are reasonable defaults,
  # but "source" is always required; "pid" is required if mode is "dl", "dl-archive" or
  # "both"; order and unit numbers are required if mode is "patron" or "both".

  def on_message(message)
    logger.debug "CreateUnitDeliverablesProcessor received: " + message.to_s

    hash = ActiveSupport::JSON.decode(message).symbolize_keys  # decode JSON message into Ruby hash
    raise "Parameter 'mode' is required" if hash[:mode].blank?
    raise "Parameter 'source' is required" if hash[:source].blank?
    raise "Parameter 'unit_id' is required" if hash[:unit_id].blank?
    raise "Parameter 'master_file_id' is required" if hash[:master_file_id].blank?

    @source = hash[:source]
    @mode = hash[:mode]
    @last = hash[:last]
    @master_file_id = hash[:master_file_id]
    
    @messagable_id = hash[:master_file_id]
    @messagable_type = "MasterFile"
    @workflow_type = AutomationMessage::WORKFLOW_TYPES_HASH.fetch(self.class.name.demodulize)

    # Watermarking variable
    @remove_watermark = hash[:remove_watermark]
    @personal_item = hash[:personal_item]
    @call_number = hash[:call_number]
    @title = hash[:title]
    @location = hash[:location]  

    if @source.match(/\.tiff?$/) and File.file?(@source)
      tiff = Magick::Image.read(@source).first

      # Directly invoke Ruby's garbage collection to clear memory
      GC.start

      # generate deliverables to be delivered directly to customer (not destined for DL)
      # set output filename (filename suffix determines format of output file)

      # Add switch to prevent jpg deliverables of personal items from having watermark.
      format = hash[:format].to_s.strip
      if format.blank? or format =~ /^jpe?g$/i
        suffix = '.jpg'
        # If the item is a personal item or if the remove_watermark value is set to 1, remove add_legal_notice (I know the syntax is confusing)
        if @personal_item
          add_legal_notice = false
        elsif @remove_watermark
          add_legal_notice = false
        else
          add_legal_notice = true
        end
      elsif format =~ /^tiff?$/i
        suffix = '.tif'
        add_legal_notice = false
      else
        raise "Unexpected format value '#{hash[:format]}'"
      end

      # In order to construct the directory for deliverables, this processor must know the order_id
      order_id = Unit.find(hash[:unit_id]).order.id

      # format output path so it includes order number and unit number, like so: .../order123/54321/...
      dest_dir = File.join(ASSEMBLE_DELIVERY_DIR, 'order_' + order_id.to_i.to_s, hash[:unit_id].to_i.to_s)
      FileUtils.mkdir_p(dest_dir)
      dest_path = File.join(dest_dir, File.basename(@source, '.*') + suffix)
       
      # make changes to original image, if applicable
      new_tiff = nil
      desired_res = hash[:desired_resolution]
      if desired_res.blank? or desired_res.to_s =~ /highest/i
        # keep original resolution
      elsif desired_res.to_i > 0
        if hash[:actual_resolution].blank?
          raise "actual_resolution is required when desired_resolution is specified"
        end
        if hash[:actual_resolution].to_i >= desired_res.to_i
          # write at desired resolution
          new_tiff = tiff.resample(desired_res.to_i)
        else
          # desired resolution not achievable; keep original resolution
        end
      else
        raise "Unexpected desired_resolution value '#{desired_res}'"
      end

      if add_legal_notice
        notice = String.new

        if @title.length < 145
          notice << "Title: #{@title}\n"
        else
          notice << "Title: #{@title[0,145]}... \n"
        end

        if @call_number
          notice << "Call Number: #{@call_number}\n"
        end

        if @location
          notice << "Location: #{@location}\n\n"
        end

        notice << "Under 17USC, Section 107, this single copy was produced for the purposes of private study, scholarship, or research.\nNo further copies should be made. Copyright and other legal restrictions may apply. Special Collections, University of Virginia Library."

        # determine point size to use, relative to image width in pixels
        point_size = (tiff.columns * 0.014).to_i  # arrived at this by trial and error; not sure why it works, but it works
          
        # determine height of bottom border (to contain six lines of text at that point size)
        bottom_border_height = (point_size * 6).to_i  # again, arrived at this by trial and error
          
        # add border (20 pixels left and right, bottom_border_height pixels top and bottom)
        bordered = tiff.border(20, bottom_border_height, 'lightgray')
          
        # add text within bottom border
        draw = Magick::Draw.new
        draw.font_family = 'times'
        draw.pointsize = point_size
        draw.gravity = Magick::SouthGravity
        draw.annotate(bordered,0,0,5,5,notice)
          
        if bottom_border_height < 100  
          # Skip the writing of a watermarked new_tif because the watermark would be too small to read
        else
          # crop to reduce top border to 20 pixels
          new_tiff = bordered.crop(Magick::SouthGravity, bordered.columns, bordered.rows - (bottom_border_height - 20))
        end
      end
        
      new_tiff = tiff if new_tiff.nil?
     
      # write output file
      new_tiff.write(dest_path)

      # Invoke Rmagick destroy! method to clear memory of legacy image information
      new_tiff.destroy!
      tiff.destroy!
     
      on_success "Deliverable image for MasterFile #{@master_file_id}."
       
      # If the file is the last of its unit to have deliverables made, the archive process can begin and the text file can be created.       
      if @last == '1'
        # Nullify @maser_file_id because we don't want the final message attached to a MasterFile, just a Unit.
        # Create @unit_id so completion message can be posted to Unit.
        @master_file_id = nil
        @unit_id = hash[:unit_id]
        @messagable = Unit.find(@unit_id)

        on_success "All patron deliverables created."
        message = ActiveSupport::JSON.encode({ :unit_id => hash[:unit_id], :mode => @mode })
        publish :delete_unit_copy_for_deliverable_generation, message
      end
    else
      raise "Source is not a .tif file: #{@source}"
    end
  end
end
