8  # Create a PDF file the contains all order metadata.  Each unit of digitization is enumerate with its Bibl records, citation statement,
# Component records, EADRef references and a list of the MasterFile images with their individual metadata.

class CreateOrderPdfProcessor < ApplicationProcessor

  subscribes_to :create_order_pdf, {:ack=>'client', 'activemq.prefetchSize' => 1}
  publishes_to :check_order_delivery_method
  
  require 'prawn'
  
  def on_message(message)
    logger.debug "CreateOrderPdfProcessor received: " + message
    
    # decode JSON message into Ruby hash
    hash = ActiveSupport::JSON.decode(message).symbolize_keys
    
    raise "Parameter 'order_id' is required" if hash[:order_id].blank?
    raise "Parameter 'fee' is required" if hash[:fee].blank?

    @order_id = hash[:order_id]
    @working_order = Order.find(@order_id)
    @messagable_id = hash[:order_id]
    @messagable_type = "Order"
    @workflow_type = AutomationMessage::WORKFLOW_TYPES_HASH.fetch(self.class.name.demodulize)
    @fee = hash[:fee]
    @customer = @working_order.customer

    @units_in_pdf = Array.new
    @working_order.units.each { |unit|        
      if unit.unit_status == 'approved'
       	@units_in_pdf.push(unit)
      end
    }

    @pdf = Prawn::Document.new
    @pdf.font "Helvetica", :encoding => nil
    @pdf.image "#{Rails.root}/app/assets/images/lib_letterhead.jpg", :position => :center, :width => 500
    @pdf.text "Digital Curation Services,  University of Virginia Library", :align => :center
    @pdf.text "Post Office Box 400155, Charlottesville, Virginia 22904 U.S.A.", :align => :center
    @pdf.text "\n\n"
    @pdf.text "Order ID: #{@working_order.id}", :align => :right, :font_size => 14
    @pdf.text "\n"
    @pdf.text "Dear #{@customer.first_name.capitalize} #{@customer.last_name.capitalize}, \n\n"  
    
    if @units_in_pdf.length > 1
      @pdf.text "On #{@working_order.date_request_submitted.strftime("%B %d, %Y")} you placed an order with Digitization Services of the University of Virginia, Charlottesville, VA.  Your request comprised #{@units_in_pdf.length} items.  Below you will find a description of your digital order and how to cite the material for publication."
    else
      @pdf.text "On #{@working_order.date_request_submitted.strftime("%B %d, %Y")} you placed an order with Digitization Services of the University of Virginia, Charlottesville, VA.  Your request comprised #{@units_in_pdf.length} item.  Below you will find a description of your digital order and how to cite the material for publication."
    end
    @pdf.text "\n"
    if not @fee.to_i.eql?(0)
      @pdf.text "Our records show that you accepted a fee of $#{@fee.to_i} for this order. This fee must be paid within 30 days.  Please write a check in the above amount made payable to <i>Digital Curation Services, UVa Library</i> and send it to the following address:", :inline_format => true
      @pdf.text "\n"
      @pdf.text "Digital Curation Services", :left => 100
      @pdf.text "University of Virginia Library", :left => 100
      @pdf.text "Post Office Box 400155", :left => 100
      @pdf.text "Charlottesville, Virginia 22904  U.S.A", :left => 100
    end

    @pdf.text "\n"
    @pdf.text "Sincerely,", :left => 350
    @pdf.text "\n"
    @pdf.text "Digitization Services Staff", :left => 350
    # End cover page

    # Begin first page of invoice
    @pdf.start_new_page

    @pdf.text "\n"
    @pdf.text "Digital Order Summary", :align => :center, :font_size => 16
    @pdf.text "\n"

    # Iterate through all the units belonging to this order
    @units_in_pdf.each { |unit|       
      # For pretty printing purposes, create pagebreak if there is less than 10 lines remaining on the current page.
      @pdf.start_new_page unless @pdf.cursor > 30

      # Add 1 to incrementation because index starts at 0
      item_number = @units_in_pdf.index(unit) + 1

      @pdf.text "Item ##{item_number}:", :font_size => 14
      @pdf.text "\n"

      # Begin work on Bibl record
      #
      # Output all present fields in Bibl record.  Almost all values in Bibl aoptional, so tests are required.
      @pdf.text "Title: #{unit.bibl.title}", :left => 14 if unit.bibl.title?
      @pdf.text "Author: #{unit.bibl.creator_name}", :left => 14 if unit.bibl.creator_name?
      @pdf.text "Call Number: #{unit.bibl.call_number}", :left => 14 if unit.bibl.call_number?
      @pdf.text "Copy: #{unit.bibl.copy}", :left => 14 if unit.bibl.copy?
      @pdf.text "Volume: #{unit.bibl.volume}", :left => 14 if unit.bibl.volume?
      @pdf.text "Issue: #{unit.bibl.issue}", :left => 14 if unit.bibl.issue?
      @pdf.text "\n"

      @pdf.text "<b>Citation:</b> <i>#{unit.bibl.get_citation}</i>", :left => 10, :inline_format => true
      @pdf.text "\n"

      # Create special tables to hold component information
      if unit.components.any?
        unit.components.each do |component|
          # Output information for this unit using the Component template
          output_component_data(component, unit.id)
        end
      else
        # Output information using the MasterFile only template.
        output_masterfile_data(unit.master_files.order(:filename))
      end
    }

    # Page numbering
    string = "page <page> of <total>"
    options = { :at => [@pdf.bounds.right - 150, 0],
              :width => 150,
              :align => :right,
              :start_count_at => 1 }
    @pdf.number_pages string, options

    # Write out the file
    @pdf.render_file(File.join("#{ASSEMBLE_DELIVERY_DIR}", "order_#{@order_id}", "#{@order_id}.pdf"))

    # Publish message
    message = ActiveSupport::JSON.encode({:order_id => @order_id})
    publish :check_order_delivery_method, message
    on_success "PDF created for order #{@order_id}."
  end 

  # Physical Component Methods
  def output_component_data(component, unit_id)
    @pdf.text "Collection Information\n", :style => :bold
    component.path_ids.each {|component_id|
      c = Component.find(component_id)

      # pdf document has a width of 540 at this point, so use that and subtract from there.
      @pdf.span(540 - component.path_ids.index(component_id) * 10, :position => :right) do
        @pdf.text"#{c.component_type.name.titleize}: #{c.name}"
      end

      @pdf.start_new_page if @pdf.cursor < 30
    }

    output_masterfile_data(component.master_files.where(:unit_id => unit_id).order(:filename))
  end

  # Methods used by both Component and EAD Ref methods
  def output_masterfile_data(sorted_master_files)
    data = Array.new
    data = [["Filename", "Title", "Description"]]
    sorted_master_files.each {|master_file|
      data += [["#{master_file.filename}", "#{master_file.title}", "#{master_file.description}"]]
    }
    @pdf.table(data, :column_widths => [140,200,200], :header => true, :row_colors => ["F0F0F0", "FFFFCC"])         
    @pdf.text "\n"

    if @pdf.cursor < 30
      @pdf.start_new_page
    end

    @pdf.text "\n"
  end
end
