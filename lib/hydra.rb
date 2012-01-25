# This module provides methods for exporting metadata to various standard XML
# formats.
module Hydra

  require 'rubygems'
  require 'net/https'
  require 'nokogiri'
  require 'solr'
  require 'uri'

  XML_FILE_CREATION_STATEMENT = "Created programmatically by the Digital Curation Services Tracking System."

  def self.marc(object)
    marcLocation = "http://search.lib.virginia.edu/catalog/#{object.catalog_id}.xml"
    return marcLocation
  end

  #-----------------------------------------------------------------------------

  # Takes a MasterFile record and returns a string containing access-rights
  # metadata, in the form of a MODS XML document.
  def self.access(object)
    case object.availability.to_s
    when 'Public', '' # default to public
      dsLocation = "http://text.lib.virginia.edu/policy/permit-to-all.xml"
    when 'VIVA only'
      dsLocation = "http://text.lib.virginia.edu/policy/permit-to-viva-only.xml"
    when 'UVA only'
      dsLocation = "http://text.lib.virginia.edu/policy/permit-to-uva-only.xml"
    when 'Restricted'
      dsLocation = "http://text.lib.virginia.edu/policy/deny-to-all.xml"
    else
      raise "Unexpected value for Unit dsLocation: #{master_file.unit.availability}"
    end
    return dsLocation
  end
  
  #-----------------------------------------------------------------------------
  def self.tei(object)
    dsLocation = "#{TEI_ACCESS_URL}?docId=#{object.content_model.name}/#{object.id}.tei.xml"
    return dsLocation
  end
 
  #-----------------------------------------------------------------------------

  def self.dc(object)
    if object.is_a? Bibl and object.catalog_id
      # MARC XML -> DC
      xslt = Nokogiri::XSLT(File.read("#{RAILS_ROOT}/lib/xslt/MARC21slim2OAIDC.xsl"))
      xml = Nokogiri::XML(open("http://search.lib.virginia.edu/catalog/#{object.catalog_id}.xml"))
      dc = xslt.transform(xml).to_xml
    else 
      # MODS -> DC
      xslt = Nokogiri::XSLT(File.read("#{RAILS_ROOT}/lib/xslt/MODS3-22simpleDC.xsl"))
      mods = Nokogiri::XML(Fedora.get_datastream("#{object.pid}", 'descMetadata', 'xml'))
      dc = xslt.transform(mods).to_xml
    end
    return dc
  end

  #-----------------------------------------------------------------------------

  # Create SOLR <add><doc> for all types of objects
  def self.solr(object)
    if object.is_a? Bibl
      # Create two String variables that hold the total data of a Bibl records' transcriptions and staff_notes
      total_transcription = String.new; total_description = String.new; total_title = String.new
      object.dl_master_files.each {|mf|
        total_transcription << mf.transcription_text + " " unless mf.transcription_text.nil?
        total_description << mf.staff_notes + " " unless mf.staff_notes.nil?
        total_title << mf.name_num + " " unless mf.name_num.nil?
      }

      external_relations = "#{FEDORA_REST_URL}/objects/#{object.pid}/datastreams/RELS-EXT/content"

#      total_transcription = total_transcription.gsub(/\r/, ' ').gsub(/\n/, ' ').gsub(/\t/, ' ').gsub(/(  )+/, ' ').gsub(/'/, '’')
#      iconv_transcription = Iconv.conv("utf-8//IGNORE", "UTF-8", total_transcription)
      # 12/8/2011 - Because Saxon is choking on large transcriptions, we will comment out this code until then and supply an empty string
      iconv_transcription = ""
            
      # total_description = total_description.gsub(/\r/, ' ').gsub(/\n/, ' ').gsub(/\t/, ' ').gsub(/(  )+/, ' ').gsub(/'/, '’')
      iconv_description = Iconv.conv("utf-8//IGNORE", "UTF-8", total_description)

      # total_title = total_title.gsub(/\r/, ' ').gsub(/\n/, ' ').gsub(/\t/, ' ').gsub(/(  )+/, ' ').gsub(/'/, '’')
      iconv_title = Iconv.conv("utf-8//IGNORE", "UTF-8", total_title)

      # external_relations = external_relations.gsub(/\r/, ' ').gsub(/\n/, ' ').gsub(/\t/, ' ').gsub(/(  )+/, ' ').gsub(/'/, '’')
      iconv_external_relations = Iconv.conv("utf-8//IGNORE", "UTF-8", external_relations)
      
      # analog_solr_record = "http://#{SOLR_PRODUCTION_NAME}:#{SOLR_PRODUCTION_PORT}/solr/select?q=id%3A#{object.catalog_id}"
      iconv_analog_solr_record = Iconv.conv("utf-8//IGNORE", "UTF-8", analog_solr_record)

#      url = "/saxon/SaxonServlet?source=#{FEDORA_REST_URL}/objects/#{object.pid}/datastreams/descMetadata/content&style=#{object.indexing_scenario.complete_url}&repository=#{FEDORA_PROXY_URL}&pid=#{object.pid}&analogSolrRecord=#{iconv_analog_solr_record}&dateIngestNow=#{Time.now.strftime('%Y%m%d%H')}&contentModel=digital_book&sourceFacet=UVA Library Digital Repository&externalRelations=#{iconv_external_relations}&totalTranscriptions=#{iconv_transcription}&totalTitles=#{iconv_title}&totalDescriptions=#{iconv_description}&clear-stylesheet-cache=yes".gsub(/ /, '%20')
      url = "/saxon/SaxonServlet?source=#{FEDORA_REST_URL}/objects/#{object.pid}/datastreams/descMetadata/content&style=#{object.indexing_scenario.complete_url}&repository=#{FEDORA_PROXY_URL}&pid=#{object.pid}&analogSolrRecord=#{iconv_analog_solr_record}&dateIngestNow=#{Time.now.strftime('%Y%m%d%H')}&contentModel=digital_book&sourceFacet=UVA Library Digital Repository&externalRelations=#{iconv_external_relations}&totalTranscriptions=#{iconv_transcription}&totalTitles=#{iconv_title}&totalDescriptions=#{iconv_description}&clear-stylesheet-cache=yes"

      Net::HTTP.start( SAXON_URL, SAXON_PORT ) do |http|
        @solr = http.get(URI.escape(url)).body
      end
    elsif object.is_a? MasterFile
      parent_mods_record = "#{FEDORA_REST_URL}/objects/#{object.bibl.pid}/datastreams/descMetadata/content"
      external_relations = "#{FEDORA_REST_URL}/objects/#{object.pid}/datastreams/RELS-EXT/content"
      
      if object.transcription_text
        # total_transcription = object.transcription_text.gsub(/\r/, ' ').gsub(/\n/, ' ').gsub(/\t/, ' ').gsub(/(  )+/, ' ').gsub(/'/, '’')
        iconv_transcription = Iconv.conv("utf-8//IGNORE", "UTF-8", total_transcription)
      else
        iconv_transcription = ''
      end
     
      if object.staff_notes
        # total_description = object.staff_notes.gsub(/\r/, ' ').gsub(/\n/, ' ').gsub(/\t/, ' ').gsub(/(  )+/, ' ').gsub(/'/, '’')
        iconv_description = Iconv.conv("utf-8//IGNORE", "UTF-8", total_description)
      else
        iconv_description = ''
      end
     
      if object.name_num
        # total_title = object.name_num.gsub(/\r/, ' ').gsub(/\n/, ' ').gsub(/\t/, ' ').gsub(/(  )+/, ' ').gsub(/'/, '’')
        iconv_title = Iconv.conv("utf-8//IGNORE", "UTF-8", total_title)
      else
        iconv_title = ''
      end

      # parent_mods_record = parent_mods_record.gsub(/\r/, ' ').gsub(/\n/, ' ').gsub(/\t/, ' ').gsub(/(  )+/, ' ').gsub(/'/, '’')
      iconv_parent_mods = Iconv.conv("utf-8//IGNORE", "UTF-8", parent_mods_record)

      # external_relations = external_relations.gsub(/\r/, ' ').gsub(/\n/, ' ').gsub(/\t/, ' ').gsub(/(  )+/, ' ').gsub(/'/, '’')
      iconv_external_relations = Iconv.conv("utf-8//IGNORE", "UTF-8", external_relations)

      # analog_solr_record = "http://#{SOLR_PRODUCTION_NAME}:#{SOLR_PRODUCTION_PORT}/solr/select?q=id%3A#{object.bibl.catalog_id}"
      iconv_analog_solr_record = Iconv.conv("utf-8//IGNORE", "UTF-8", analog_solr_record)

      url = "/saxon/SaxonServlet?source=#{FEDORA_REST_URL}/objects/#{object.pid}/datastreams/descMetadata/content&style=#{object.indexing_scenario.complete_url}&repository=#{FEDORA_PROXY_URL}&pid=#{object.pid}&analogSolrRecord=#{iconv_analog_solr_record}&dateIngestNow=#{Time.now.strftime('%Y%m%d%H')}&contentModel=jp2k&sourceFacet=UVA Library Digital Repository&externalRelations=#{iconv_external_relations}&totalTranscriptions=#{iconv_transcription}&totalTitles=#{iconv_title}&totalDescriptions=#{iconv_description}&parentModsRecord=#{iconv_parent_mods}&clear-stylesheet-cache=yes".gsub(/ /, '%20')

      Net::HTTP.start( SAXON_URL, SAXON_PORT ) do |http|
        @solr = http.get(url).body
      end
    elsif object.is_a? Component
    else
      raise "Unexpected object type passed to Hydra.solr.  Please inspect code"
    end
    return @solr
  end

  # Below is the previous version of the Hydra.solr method.  Will remove in time after transition to Saxon is 100% certain.

  # def self.solr(object)
  #   if object.is_a? Bibl
  #     # Create two String variables that hold the total data of a Bibl records' transcriptions and staff_notes
  #     total_transcription = String.new; total_description = String.new; total_title = String.new
  #     object.dl_master_files.each {|mf|
  #       total_transcription << mf.transcription_text + " " unless mf.transcription_text.nil?
  #       total_description << mf.staff_notes + " " unless mf.staff_notes.nil?
  #       total_title << mf.name_num + " " unless mf.name_num.nil?
  #     }

  #     external_relations = "#{FEDORA_REST_URL}/objects/#{object.pid}/datastreams/RELS-EXT/content"

  #     total_transcription = total_transcription.gsub(/\r/, ' ').gsub(/\n/, ' ').gsub(/\t/, ' ').gsub(/(  )+/, ' ').gsub(/'/, '’')  
  #     iconv_transcription = Iconv.conv("utf-8//IGNORE", "UTF-8", total_transcription)
      
  #     total_description = total_description.gsub(/\r/, ' ').gsub(/\n/, ' ').gsub(/\t/, ' ').gsub(/(  )+/, ' ').gsub(/'/, '’')
  #     iconv_description = Iconv.conv("utf-8//IGNORE", "UTF-8", total_description)

  #     total_title = total_title.gsub(/\r/, ' ').gsub(/\n/, ' ').gsub(/\t/, ' ').gsub(/(  )+/, ' ').gsub(/'/, '’')
  #     iconv_title = Iconv.conv("utf-8//IGNORE", "UTF-8", total_title)

  #     external_relations = external_relations.gsub(/\r/, ' ').gsub(/\n/, ' ').gsub(/\t/, ' ').gsub(/(  )+/, ' ').gsub(/'/, '’')
  #     iconv_external_relations = Iconv.conv("utf-8//IGNORE", "UTF-8", external_relations)
      
  #     doc = Nokogiri::XML(open("#{FEDORA_REST_URL}/objects/#{object.pid}/datastreams/descMetadata/content"))
  #     xslt = Nokogiri::XSLT(File.read("/usr/local/projects/tracksys/lib/xslt/defaultModsTransformation.xsl")) 
      
  #     analog_solr_record = "http://#{SOLR_PRODUCTION_NAME}:#{SOLR_PRODUCTION_PORT}/solr/select?q=id%3A#{object.catalog_id}"
  #     iconv_analog_solr_record = Iconv.conv("utf-8//IGNORE", "UTF-8", analog_solr_record)

  #     @solr = xslt.transform(doc,
  #       ['pid', "'#{object.pid}'",
  #       'repository', "'#{FEDORA_PROXY_URL}'",
  #       'analogSolrRecord', "'#{iconv_analog_solr_record}'",
  #       'dateIngestNow', "'#{Time.now.strftime("%Y%m%d%H")}'",
  #       'contentModel', "'digital_book'",
  #       'sourceFacet', "'UVA Library Digital Repository'",         
  #       'externalRelations', "'#{iconv_external_relations}'",
  #       'totalTranscriptions', "'#{iconv_transcription}'",
  #       'totalTitles', "'#{iconv_title}'",
  #       'totalDescriptions', "'#{iconv_description}'"])
      
  #   elsif object.is_a? MasterFile
  #     parent_mods_record = "#{FEDORA_REST_URL}/objects/#{object.bibl.pid}/datastreams/descMetadata/content"
  #     external_relations = "#{FEDORA_REST_URL}/objects/#{object.pid}/datastreams/RELS-EXT/content"
      
  #     if object.transcription_text
  #       total_transcription = object.transcription_text.gsub(/\r/, ' ').gsub(/\n/, ' ').gsub(/\t/, ' ').gsub(/(  )+/, ' ').gsub(/'/, '’')
  #       iconv_transcription = Iconv.conv("utf-8//IGNORE", "UTF-8", total_transcription)
  #     else
  #       iconv_transcription = ''
  #     end
     
  #     if object.staff_notes
  #       total_description = object.staff_notes.gsub(/\r/, ' ').gsub(/\n/, ' ').gsub(/\t/, ' ').gsub(/(  )+/, ' ').gsub(/'/, '’')
  #       iconv_description = Iconv.conv("utf-8//IGNORE", "UTF-8", total_description)
  #     else
  #       iconv_description = ''
  #     end
     
  #     if object.name_num
  #       total_title = object.name_num.gsub(/\r/, ' ').gsub(/\n/, ' ').gsub(/\t/, ' ').gsub(/(  )+/, ' ').gsub(/'/, '’')
  #       iconv_title = Iconv.conv("utf-8//IGNORE", "UTF-8", total_title)
  #     else
  #       iconv_title = ''
  #     end

  #     parent_mods_record = parent_mods_record.gsub(/\r/, ' ').gsub(/\n/, ' ').gsub(/\t/, ' ').gsub(/(  )+/, ' ').gsub(/'/, '’')
  #     iconv_parent_mods = Iconv.conv("utf-8//IGNORE", "UTF-8", parent_mods_record)

  #     external_relations = external_relations.gsub(/\r/, ' ').gsub(/\n/, ' ').gsub(/\t/, ' ').gsub(/(  )+/, ' ').gsub(/'/, '’')
  #     iconv_external_relations = Iconv.conv("utf-8//IGNORE", "UTF-8", external_relations)

  #     analog_solr_record = "http://#{SOLR_PRODUCTION_NAME}:#{SOLR_PRODUCTION_PORT}/solr/select?q=id%3A#{object.bibl.catalog_id}"
  #     iconv_analog_solr_record = Iconv.conv("utf-8//IGNORE", "UTF-8", analog_solr_record)
      
  #     doc = Nokogiri::XML(open("#{FEDORA_REST_URL}/objects/#{object.pid}/datastreams/descMetadata/content"))
  #     xslt = Nokogiri::XSLT(File.read("/usr/local/projects/tracksys/lib/xslt/defaultModsTransformation.xsl"))
    
  #     @solr = xslt.transform(doc,
  #       ['pid', "'#{object.pid}'",
  #       'repository', "'#{FEDORA_PROXY_URL}'",
  #       'analogSolrRecord', "'#{iconv_analog_solr_record}'",
  #       'dateIngestNow', "'#{Time.now.strftime("%Y%m%d%H")}'",
  #       'contentModel', "'jp2k'",
  #       'sourceFacet', "'UVA Library Digital Repository'",
  #       'parentModsRecord', "'#{iconv_parent_mods}'",
  #       'externalRelations', "'#{iconv_external_relations}'",
  #       'totalTranscriptions', "'#{iconv_transcription}'",
  #       'totalTitles', "'#{iconv_title}'",
  #       'totalDescriptions', "'#{iconv_description}'"])
                                                                                  
  #   elsif object.is_a? Component
  #   elsif object.is_a? EadRef
  #   else
  #     raise "Unexpected object type passed to Hydra.solr.  Please inspect code"
  #   end  
  #   return @solr.to_xml
  # end

  #-----------------------------------------------------------------------------

  # given the output of an object's solr_xml method, return a
  # solr-ruby object, e.g., doc = read_solr_xml(bibl.solr_xml)
  def self.read_solr_xml(solr_xml)
    xml = Nokogiri::XML(solr_xml)
    doc = Solr::Document.new
 
    # The Hash has to be rebuilt at every element so to allow repeatable solr fields (i.e. subject_text).   
    xml.xpath("//field").each { |e|
      h = Hash.new
      h[e['name']] = e.content
      doc << h
    }
         
    return doc
  end

  #-----------------------------------------------------------------------------
  
  # Takes a MasterFile record representing an image (tech_meta_type = "image")
  # and returns a string containing technical metadata, in the form of a MIX
  # XML document. See http://www.loc.gov/standards/mix/
  def self.tech(object)
    output = ''
    xml = Builder::XmlMarkup.new(:target => output, :indent => 2)
    xml.instruct! :xml  # Include XML declaration
    tech_meta = object.image_tech_meta
    xml.mix(:mix,
      "xmlns:mix".to_sym => Fedora_namespaces['mix'],
      "xmlns:xsi".to_sym => Fedora_namespaces['xsi'],
      "xsi:schemaLocation".to_sym => Fedora_namespaces['mix'] + ' ' + Schema_locations['mix']
      ) do
      xml.mix :BasicDigitalObjectInformation do
        # filename
        if object.filename
          xml.mix :ObjectIdentifier do
            xml.mix :objectIdentifierType, 'filename'
            xml.mix :objectIdentifierValue, object.filename
          end
        end
        
        # PID (U.Va. Library permanent identifier)
        if object.pid
          xml.mix :ObjectIdentifier do
            xml.mix :objectIdentifierType, 'pid'
            xml.mix :objectIdentifierValue, object.pid
          end
        end
        
        # file size
        xml.mix :fileSize, object.filesize if object.filesize
        
        # file format
        xml.mix :FormatDesignation do
          xml.mix :formatName, tech_meta.mime_type
        end
        
        # compression
        if tech_meta.compression
          if tech_meta.compression.match(/(none|uncompressed)/i)
            compression_scheme = 'Uncompressed'
          else
            compression_scheme = tech_meta.compression
          end
          xml.mix :Compression do
            xml.mix :compressionScheme, compression_scheme
          end
        end
      end  # </mix:BasicDigitalObjectInformation>
      
      xml.mix :BasicImageInformation do
        xml.mix :BasicImageCharacteristics do
          # image width/height
          xml.mix :imageWidth, tech_meta.width if tech_meta.width
          xml.mix :imageHeight, tech_meta.height if tech_meta.height
          
          # color space
          if tech_meta.color_space
            xml.mix :PhotometricInterpretation do
              xml.mix :colorSpace, tech_meta.color_space
            end
          end
        end
      end  # </mix:BasicImageInformation>
      
      xml.mix :ImageAssessmentMetadata do
        # resolution
        if tech_meta.resolution and tech_meta.resolution_unit
          xml.mix :SpatialMetrics do
            if tech_meta.resolution_unit.match(/^dpi$/i)
              xml.mix :samplingFrequencyUnit, 'in.'
              xml.mix :xSamplingFrequency do
                xml.mix :numerator, tech_meta.resolution
              end
              xml.mix :ySamplingFrequency do
                xml.mix :numerator, tech_meta.resolution
              end
            else
              raise "Unexpected value '#{tech_meta.resolution_unit}' for resolution_unit on image_tech_meta #{tech_meta.id}"
            end
          end  # </mix:SpatialMetrics>
        end
        
        # depth
        if tech_meta.depth
          if tech_meta.depth == 1 or tech_meta.depth == 8
            bits_per_sample = tech_meta.depth
            samples_per_pixel = 1
          elsif tech_meta.depth == 24
            bits_per_sample = 8
            samples_per_pixel = 3
          else
            raise "Unexpected value '#{tech_meta.depth}' for depth on image_tech_meta #{tech_meta.id}"
          end
          xml.mix :ImageColorEncoding do
            xml.mix :BitsPerSample do
              xml.mix :bitsPerSampleValue, bits_per_sample
              xml.mix :bitsPerSampleUnit, 'integer'
            end
            xml.mix :samplesPerPixel, samples_per_pixel
          end  # </mix:ImageColorEncoding>
        end
      end  # </mix:ImageAssessmentMetadata>
    end  # </mix:mix>
  end
  
  #-----------------------------------------------------------------------------
  
  # Takes a Bibl, Component, or MasterFile record and returns a string
  # containing metadata indicating external relationships (Fedora RELS-EXT
  # datastream), in the form of an RDF XML document.
  def self.rels_ext(object)
    unless object.respond_to?(:pid)
      raise ArgumentError, "Object passed must have a 'pid' attribute"
    end
    if object.pid.blank?
      raise ArgumentError, "Can't export #{object.class} #{object.id}: pid is blank"
    end
    
    output = ''
    xml = Builder::XmlMarkup.new(:target => output, :indent => 2)
    xml.instruct! :xml  # Include XML declaration
    
    xml.rdf(:RDF,
      "xmlns:fedora-model".to_sym => Fedora_namespaces['fedora-model'],
      "xmlns:rdf".to_sym => Fedora_namespaces['rdf'],
      "xmlns:rdfs".to_sym => Fedora_namespaces['rdfs'],
      "xmlns:rel".to_sym => Fedora_namespaces['rel'], 
      "xmlns:uva".to_sym => Fedora_namespaces['uva']
      ) do
      xml.rdf(:Description, "rdf:about".to_sym => "info:fedora/#{object.pid}") do

        # Create isMemberof relationship in rels-ext
        # For a Component or MasterFile object, indicate parent/child relationship using <rel:isMemberOf>
        if object.is_a? Component
          if object.parent_component
            parent_pid = object.parent_component.pid
            xml.uva :isConstituentOf, "rdf:resource".to_sym => "info:fedora/#{parent_pid}"
          else
            parent_pid = object.bibl.pid
            xml.uva :hasCatalogRecordIn, "rdf:resource".to_sym => "info:fedora/#{parent_pid}"
          end
        elsif object.is_a? MasterFile
          if object.component
            parent_pid = object.component.pid
            xml.uva :isConstituentOf, "rdf:resource".to_sym => "info:fedora/#{parent_pid}"
        else
            parent_pid = object.unit.bibl.pid
            xml.uva :hasCatalogRecordIn, "rdf:resource".to_sym => "info:fedora/#{parent_pid}"
          end
        elsif object.is_a? Bibl
          if object.parent_bibl
            parent_pid = object.parent_bibl
            xml.uva :hasCatalogRecordIn, "rdf:resource".to_sym => "info:fedora/#{parent_pid}"
          end
        else
        end

        # Acquire PID of image that has been selected as the exemplar image for this Bibl.
        # Exemplar images are used in the Blacklight display on the _index_partial/_dl_jp2k view.
        if object.is_a? Bibl
          if object.exemplar
            exemplar_master_file = MasterFile.find(:first, :conditions => "filename = '#{object.exemplar}'")
            pid = exemplar_master_file.pid
            xml.uva :hasExemplar, "rdf:resource".to_sym => "info:fedora/#{pid}"
          else
            # Using the mean of the files output from the method in Bibl model to get only those masterfiles
            # associated with this Bibl record that belong to units that have already been queued for ingest.
            #
            # dl_master_files might return Nil prior to ingest, so we will use the master_files method
            mean_of_master_files = object.master_files.length / 2
            pid = object.master_files[mean_of_master_files.to_i].pid

            # save master file designated as the exemplar to the Bibl record
            object.exemplar = object.master_files[mean_of_master_files.to_i].filename
            object.save!

            xml.uva :hasExemplar, "rdf:resource".to_sym => "info:fedora/#{pid}"
          end
        end
        
        # Create sequential relationships: hasPreceedingPage, hasFollowingPage
        if object.is_a? MasterFile
          if object.preceeding_pid
            xml.uva :hasPreceedingPage, "rdf:resource".to_sym => "info:fedora/#{object.preceeding_pid}"
            xml.uva :isFollowingPageOf, "rdf:resource".to_sym => "info:fedora/#{object.preceeding_pid}"
          end
          if object.following_pid
            xml.uva :hasFollowingPage, "rdf:resource".to_sym => "info:fedora/#{object.following_pid}"
            xml.uva :isPreceedingPageOf, "rdf:resource".to_sym => "info:fedora/#{object.following_pid}"
          end
        end

        # Indicate content model using <fedora-model:hasModel>
        content_models = Array.new
        content_models.push(Fedora_content_models['indexable'])
        content_models.push(Fedora_content_models['hydra-common-metadata'])
        if object.is_a? Bibl or object.is_a? Component
          content_models.push(Fedora_content_models['hydra-generic-parent'])
          content_models.push(Fedora_content_models['fedora-generic'])
        elsif object.is_a? MasterFile and object.tech_meta_type == 'image'
          content_models.push(Fedora_content_models['hydra-generic-content'])
          content_models.push(Fedora_content_models['jp2k'])
        elsif object.is_a? MasterFile and object.tech_meta_type == 'text'
#          content_models.push(Fedora_content_models['text'])
        else
          content_model = nil
        end
        if not content_models.empty?
          content_models.each {|content_model|
            xml.__send__ "fedora-model".to_sym, :hasModel, "rdf:resource".to_sym => "info:fedora/#{content_model}"
          }
        end
      end
    end
    
    return output
  end
  #-----------------------------------------------------------------------------
  
  # Takes a Bibl, Component, or MasterFile record and returns a string
  # containing metadata indicating external relationships (Fedora RELS-INT
  # datastream), in the form of an RDF XML document.
  def self.rels_int(object)
    unless object.respond_to?(:pid)
      raise ArgumentError, "Object passed must have a 'pid' attribute"
    end
    if object.pid.blank?
      raise ArgumentError, "Can't export #{object.class} #{object.id}: pid is blank"
    end
    
    output = ''
    xml = Builder::XmlMarkup.new(:target => output, :indent => 2)
    xml.instruct! :xml  # Include XML declaration
    
    xml.rdf(:RDF,
      "xmlns:fedora-model".to_sym => Fedora_namespaces['fedora-model'],
      "xmlns:rdf".to_sym => Fedora_namespaces['rdf'],
      "xmlns:rdfs".to_sym => Fedora_namespaces['rdfs'],
      "xmlns:uva".to_sym => Fedora_namespaces['uva'] ) do

        xml.rdf(:Description, "rdf:about".to_sym => "info:fedora/#{object.pid}/descMetadata") do
          xml.uva :hasIndexer, "rdf:resource".to_sym => "info:fedora/#{object.indexing_scenario.pid}/#{object.indexing_scenario.datastream_name}"
        end   

        # All objects - Link to descMetadata transformation
        if object.is_a? MasterFile
          # TODO: If we start ingesting video and other content as MasterFile objects, we will need to make this 
          # assignemnt of relationships more granular.  For now, we will only do descMetadata transformation for images.
          
#          xml.rdf(:Description, "rdf:about".to_sym => "info:fedora/#{object.pid}/descMetadata") do
#            xml.__send__ "fedora-model".to_sym, :downloadFilename, 'andrew'
#            xml.fedora-model :downloadFilename, "rdf:resource".to_sym => "andrew"
#          end   

          case object.tech_meta_type
          when 'image'
            # Link to image descMetadata transformation (only for images)
          else  
            # When the time comes, put in other transformations
          end
        elsif object.is_a? Bibl
          # TODO?: Conditional transformation of a Bibl object's descMetadata depending on whether that datastreams was populated through a 
          # MARC -> MODS transformation or the MODS is custom created.

          # Create a default transformation for bibl records if they have catalog_id (i.e. their MODS comes from MARC XML

        elsif object.is_a? Component
        elsif object.is_a? EadRef
        else
        end
      end
    return output
  end
  
  #-----------------------------------------------------------------------------
  
  # Takes a Bibl, Component, or MasterFile record and returns a string
  # containing descriptive metadata, in the form of a MODS XML document. See
  # http://www.loc.gov/standards/mods/
  #
  # By default, all Units associated with the Bibl are exported. Optionally
  # takes an array of Unit records which serves as a filter for the Units to
  # be exported; that is, a Unit must be included in the array passed to be
  # included in the export.
  def self.desc(object, units_filter = nil)
    # If there is a Bibl with MARC XML available, that MARC XML will be transformed into
    # the MODS that will be ingested as the Hydra-compliant descMetadata
    if object.is_a? Bibl and object.catalog_id
      output = mods_from_marc(object)
    else
      output = ''
      xml = Builder::XmlMarkup.new(:target => output, :indent => 2)
      xml.instruct! :xml  # Include XML declaration
    
      if object.is_a? Bibl
        mods_bibl(xml, object, units_filter)
      else
        xml.mods(:mods,
          "xmlns:mods".to_sym => Fedora_namespaces['mods'],
          "xmlns:xsi".to_sym => Fedora_namespaces['xsi'],
          "xsi:schemaLocation".to_sym => Fedora_namespaces['mods'] + ' ' + Schema_locations['mods']
          ) do
          if object.is_a? Component
            mods_component(xml, object)
          elsif object.is_a? MasterFile
            mods_master_file(xml, object)
          elsif object.is_a? EadRef
          end
        end
      end
    end  
    return output
  end
  
  def self.mods_from_marc(object)
    xslt = Nokogiri::XSLT(File.read("#{RAILS_ROOT}/lib/xslt/MARC21slim2MODS3-4.xsl"))
    xml = Nokogiri::XML(open("http://search.lib.virginia.edu/catalog/#{object.catalog_id}.xml"))
    mods = xslt.transform(xml, ['barcode', "'#{object.barcode}'", 'identifiers', "'#{TRACKSYS_URL_METADATA}/#{object.class.to_s.underscore}/mods_identifiers/#{object.id}'"])
    return mods.to_xml
  end  
#  private_class_method :mods_from_marc

  #-----------------------------------------------------------------------------
  # Method definitions for descriptive metadata, using MODS (3.3)
  # See http://www.loc.gov/standards/mods/
  #-----------------------------------------------------------------------------

  def self.mods_identifier_partial(object)
    output = ''
    xml = Builder::XmlMarkup.new(:target => output, :indent => 2)
    xml.instruct! :xml  # Include XML declaration
 
    xml.mods(:mods,
      "xmlns:mods".to_sym => Fedora_namespaces['mods'],
      "xmlns:xsi".to_sym => Fedora_namespaces['xsi'],
      "xsi:schemaLocation".to_sym => Fedora_namespaces['mods'] + ' ' + Schema_locations['mods']
      ) do

      xml.mods :identifier, object.pid, :type =>'pid', :displayLabel => 'UVA Library Fedora Repository PID'
      
      if object.is_a? Bibl
        if object.discoverability
          xml.mods :identifier, object.pid, :type =>'uri', :displayLabel => 'Accessible index record displayed in VIRGO'
        else
          xml.mods :identifier, object.pid, :type =>'uri', :displayLabel => 'Accessible index record displayed in VIRGO', :invalid => 'yes'
        end
        
        if not object.legacy_identifiers.empty?
          object.legacy_identifiers.each {|li|
            xml.mods :identifier, "#{li.legacy_identifier}", :type => 'legacy', :displayLabel => "#{li.description}"
          }
        end

        xml.mods :identifier, object.id, :type =>'local', :displayLabel => 'Digitization Services Tracksys Bibl ID'
        
        # Include all the Unit number of units belonging to the Bibl that have include_in_dl = true
        object.units.each {|unit|
          if unit.include_in_dl == true
            xml.mods :identifier, unit.id, :type =>'local', :displayLabel => 'Digitization Services Tracksys Unit ID'
          end
        }
      elsif object.is_a? MasterFile
        
        xml.mods :identifier, object.unit.id, :type => 'local', :displayLabel => 'Digitization Services Tracksys Unit ID'
        xml.mods :identifier, object.id, :type => 'local', :displayLabel => 'Digitization Services Tracksys MasterFile ID'
        xml.mods :identifier, object.filename, :type => 'local', :displayLabel => 'Digitization Services Archive Filename'

        if object.discoverability
          xml.mods :identifier, object.pid, :type =>'uri', :displayLabel => 'Accessible index record displayed in VIRGO'
        else
          xml.mods :identifier, object.pid, :type =>'uri', :displayLabel => 'Accessible index record displayed in VIRGO', :invalid => 'yes'
        end
      end
    end
    return output
  end

  # Outputs descriptive metadata for a Bibl record as a MODS document
  def self.mods_bibl(xml, bibl, units_filter)
    # start <mods:mods> element
    xml.mods(:mods,
      "xmlns:mods".to_sym => Fedora_namespaces['mods'],
      "xmlns:xsi".to_sym => Fedora_namespaces['xsi'],
      "xsi:schemaLocation".to_sym => Fedora_namespaces['mods'] + ' ' + Schema_locations['mods']
      ) do

      # Put PID for object into MODS.  In order to transform this into a SOLR doc, there must be a PID in the MODS.
      xml.mods :identifier, bibl.pid, :type =>'pid', :displayLabel => 'UVA Library Fedora Repository PID'
             
      # Create an identifier statement that indicates whether this item will be uniquely discoverable in VIRGO.  Default for an individual bibl will be to 
      # display the SOLR record (i.e. no 'invalid' attribute).  Will draw value from bibl.discoverability.
      xml.mods :identifier, bibl.pid, :type =>'uri', :displayLabel => 'Accessible index record displayed in VIRGO'

      # type of resource
      if bibl.is_manuscript? and bibl.is_collection?
        xml.mods :typeOfResource, bibl.resource_type, :manuscript => 'yes', :collection => 'yes'
      elsif bibl.is_manuscript?
        xml.mods :typeOfResource, bibl.resource_type, :manuscript => 'yes'
      elsif bibl.is_collection?
        xml.mods :typeOfResource, bibl.resource_type, :collection => 'yes'
      else
        xml.mods :typeOfResource, bibl.resource_type
      end
      
      # genre
      unless bibl.genre.blank?
        xml.mods :genre, bibl.genre, :authority => 'marcgt'
      end
      
      # title
      unless bibl.title.blank?
        xml.mods :titleInfo do
          xml.mods :title, bibl.title
        end
      end
      
      # description
      unless bibl.description.blank?
        xml.mods :abstract, bibl.description
      end
      
      # creator
      unless bibl.creator_name.blank?
        if bibl.creator_name_type.blank?
          # omit 'type' attribute
          xml.mods :name do
            xml.mods :namePart, bibl.creator_name
          end
        else
          # include 'type' attribute
          xml.mods :name, :type => bibl.creator_name_type do
            xml.mods :namePart, bibl.creator_name
          end
        end
      end
      
      mods_originInfo(xml, bibl, units_filter)
      mods_physicalDescription(xml, bibl, units_filter)
      mods_location(xml, bibl)
      mods_recordInfo(xml, bibl)
      
      # Include each associated MasterFile as a <mods:relatedItem>
      
      # Find the Components, if any, associated with this Bibl. (First, look
      # for top-level components only; if found, each child component will be
      # handled later by mods_component() below.)
#      components = Component.find(:all, :conditions => "bibl_id = #{bibl.id} AND parent_component_id = 0", :order => "seq_number, id")
#      if components.blank?
#        # No top-level Components associated with this Bibl; find any/all Components
#        components = Component.find(:all, :conditions => "bibl_id = #{bibl.id}", :order => "seq_number, id")
#      end
      
#      if components.blank?
        # No Components associated with this Bibl; output list of MasterFiles
        # grouped by Units (not Components)
        # Output a <mods:relatedItem> for each Unit
#        count = 0
#        bibl.units.each do |unit|
#          next unless UnitsFilter.process_unit?(unit, units_filter)
#          xml.mods :relatedItem, :ID => "unit_#{unit.id}", :type => 'constituent' do
#            # Output a <mods:relatedItem> for each MasterFile
#            unit.master_files.sort_by{|mf| mf.filename}.each do |master_file|
#              count += 1
#              mods_master_file(xml, master_file, count)
#            end
#          end
#        end
#      else
        # This Bibl has associated Components; output list of MasterFiles
        # grouped by Components (not Units)
#        components.each do |component|
#          mods_component(xml, component)
#        end
#      end
      
    end  # </mods:mods>
  end
  private_class_method :mods_bibl

  #-----------------------------------------------------------------------------
  
  # Outputs a Component record as a +mods:relatedItem+ element
  def self.mods_component(xml, component)
    if component.seq_number.blank?
      display_label = component.component_type.name.capitalize
    else
      display_label = "#{component.component_type.name.capitalize} #{component.seq_number}"
    end
    
    if component.pid.blank?
      relatedItem_id = "component_#{component.id}"
    else
      relatedItem_id = format_pid(component.pid)
    end
    xml.mods :relatedItem, :displayLabel => display_label, :ID => relatedItem_id, :type => 'constituent' do
      # title
      unless component.title.blank?
        xml.mods :titleInfo do
          xml.mods :title, component.title
        end
      end
      
      # label
      unless component.label.blank?
        xml.mods :titleInfo do
          xml.mods :title, component.label
        end
      end
      
      # date
      unless component.date.blank?
        xml.mods :originInfo do
          xml.mods :dateCreated, component.date
        end
      end
      
      # content description
      unless component.content_desc.blank?
        xml.mods :abstract, component.content_desc
      end
      
      # identifiers
      unless component.idno.blank?
        xml.mods :identifier, component.idno, :type => 'local', :displayLabel => 'Local identifier'
      end
      unless component.barcode.blank?
        xml.mods :identifier, component.barcode, :type => 'local', :displayLabel => 'Barcode'
      end
      
      # Include each associated MasterFile as a nested <mods:relatedItem>
      count = 0
      component.master_files.sort_by{|mf| mf.filename}.each do |master_file|
        count += 1
        mods_master_file(xml, master_file, count)
      end
      
      # Output each child Component as a nested <mods:relatedItem>
      component.child_components.each do |child_component|
        mods_component(xml, child_component)
      end
    end
  end
  private_class_method :mods_component

  #-----------------------------------------------------------------------------

  # Outputs a +mods:location+ element
  def self.mods_location(xml, bibl)
    xml.mods :location do
      if bibl.is_personal_item
        xml.mods :physicalLocation, '[personal copy]'
      else
        #xml.mods :physicalLocation, 'University of Virginia Library'
        xml.mods :physicalLocation, 'viu', :authority => 'marcorg'
      end
      
      xml.mods :url, @xml_file_name, :usage => 'primary display', :access => 'object in context'
      
      unless bibl.copy.blank?
        xml.mods :holdingSimple do
          xml.mods :copyInformation do
            xml.mods :enumerationAndChronology, "copy #{bibl.copy}"
          end
        end
      end
    end
  end
  private_class_method :mods_location

  #-----------------------------------------------------------------------------

  # Outputs a MasterFile record as a +mods:relatedItem+ element
  def self.mods_master_file(xml, master_file, count = nil)

    # Put PID for object into MODS.  In order to transform this into a SOLR doc, there must be a PID in the MODS.
    xml.mods :identifier, master_file.pid, :type =>'pid', :displayLabel => 'UVA Library Fedora Repository PID'
  
    # Create an identifier statement that indicates whether this item will be uniquely discoverable in VIRGO.  Default for an individual master_file will be to 
    # hide the SOLR record (i.e. make :invalid => 'yes').  Will draw value from master_file.discoverability.
    if master_file.discoverability
      xml.mods :identifier, master_file.pid, :type =>'uri', :displayLabel => 'Accessible index record displayed in VIRGO'
    else
      xml.mods :identifier, master_file.pid, :type =>'uri', :displayLabel => 'Accessible index record displayed in VIRGO', :invalid => 'yes'
    end
    
    xml.mods :identifier, master_file.unit.id, :type => 'local', :displayLabel => 'Digitization Services Tracksys Unit ID'
    
    xml.mods :identifier, master_file.id, :type => 'local', :displayLabel => 'Digitization Services Tracksys MasterFile ID'
    
    xml.mods :identifier, master_file.filename, :type => 'local', :displayLabel => 'Digitization Services Archive Filename'
    
    if not master_file.legacy_identifiers.empty?
      master_file.legacy_identifiers.each {|li|
        xml.mods :identifier, "#{li.legacy_identifier}", :type => 'legacy', :displayLabel => "#{li.description}"
      }
   end    

    case master_file.tech_meta_type
    when 'image'
      display_label = "Image"
    when 'text'
      display_label = "#{master_file.text_tech_meta.text_format} text resource"
    else
      raise "Unexpected tech_meta_type value '#{master_file.tech_meta_type}' on master_file #{master_file.id}"
    end

    if master_file.pid.blank?
      relatedItem_id = "#{master_file.tech_meta_type}_#{master_file.id}"
    else
      relatedItem_id = format_pid(master_file.pid)
    end

    xml.mods :titleInfo do
      if master_file.name_num.blank?
        if count.nil?
          title = "[#{display_label}]"
        else
          title = "[#{display_label} #{count}]"
        end
        xml.mods :title, title
      else
        xml.mods :title, master_file.name_num
      end
    end
    if master_file.staff_notes
      xml.mods :note, master_file.staff_notes
    end
  end
  private_class_method :mods_master_file
  
  #-----------------------------------------------------------------------------

  # Outputs a +mods:originInfo+ element
  def self.mods_originInfo(xml, bibl, units_filter)
    xml.mods :originInfo do
      # date captured (date of digitization)
      # Looking at the units associated with this bibl record, use the latest
      # date_completed value.
      date_completed = nil
      bibl.units.each do |unit|
        next unless UnitsFilter.process_unit?(unit, units_filter)
        if not unit.date_archived.blank?
          if date_completed.blank?
            date_completed = unit.date_archived
          elsif unit.date_archived > date_completed
            date_completed = unit.date_archived
          end
        end
      end
      unless date_completed.blank?
        xml.mods :dateCaptured, date_completed.strftime("%Y-%m-%d")
      end
      
      # publisher of digital resource
      xml.mods :publisher, 'University of Virginia Library'
      xml.mods :place do
        xml.mods :placeTerm, 'Charlottesville, VA'
      end
    end
  end
  private_class_method :mods_originInfo

  #-----------------------------------------------------------------------------

  # Outputs a +mods:physicalDescription+ element
  def self.mods_physicalDescription(xml, bibl, units_filter)
    xml.mods :physicalDescription do
      # Determine extent -- that is, number of files. First preference is to count
      # MasterFile records associated with this bibl record; second is
      # unit_extent_actual value; last resort is unit_extent_estimated value.
      c = 0
      bibl.units.each do |unit|
        next unless UnitsFilter.process_unit?(unit, units_filter)
        if unit.master_files.size > 0
          c += unit.master_files.size
        elsif unit.unit_extent_actual.to_i > 0
          c += unit.unit_extent_actual
        elsif unit.unit_extent_estimated.to_i > 0
          c += unit.unit_extent_estimated
        end
      end
      xml.mods :extent, c.to_s + ' ' + (c == 1 ? 'file' : 'files') if c > 0
      
      # <digitalOrigin> uses a controlled vocabulary; use "reformatted digital"
      # meaning "resource was created by digitization of the original non-digital
      # form" (MODS documentation).
      xml.mods :digitalOrigin, 'reformatted digital'
      
      # List the mime types applicable to this bibl record (based on the
      # MasterFile records associated with this bibl record).
      # build hash of mime types 
      mime_types = Hash.new
      bibl.units.each do |unit|
        next unless UnitsFilter.process_unit?(unit, units_filter)
        unit.master_files.each do |master_file|
          mime_types[master_file.mime_type] = nil
        end
      end
      # output list of mime types
      mime_types.each_key do |mime_type|
        xml.mods :internetMediaType, mime_type
      end
    end
  end
  private_class_method :mods_physicalDescription

  #-----------------------------------------------------------------------------

  # Outputs a +mods:recordInfo+ element
  def self.mods_recordInfo(xml, bibl)
    xml.mods :recordInfo do
      # organization that created this MODS metadata record
      xml.mods :recordContentSource, 'viu', :authority => 'marcorg'
      
      # creation date for this MODS metadata record
      xml.mods :recordCreationDate, Time.now.strftime("%Y%m%d"), :encoding => 'w3cdtf'
      
      # origin of this MODS metadata record
      xml.mods :recordOrigin, XML_FILE_CREATION_STATEMENT
      
      # language of this MODS metadata record (English)
      xml.mods :languageOfCataloging do
        xml.mods :languageTerm, 'en', :type => 'code', :authority => 'rfc3066'
      end
    end
  end
  private_class_method :mods_recordInfo

  #-----------------------------------------------------------------------------

  # Outputs metadata about the physical source for a Bibl record, using MODS
  def self.mods_source(xml, bibl)
    xml.mods :relatedItem, :type => 'original' do
      
      # identifiers
      unless bibl.catalog_id.blank?
        xml.mods :identifier, bibl.catalog_id, :type => 'local', :displayLabel => 'Catalog key'
      end
      unless bibl.title_control.blank?
        xml.mods :identifier, bibl.title_control, :type => 'local', :displayLabel => 'Title control number'
      end
      unless bibl.barcode.blank?
        xml.mods :identifier, bibl.barcode, :type => 'local', :displayLabel => 'Barcode'
      end
      
      # classification (call number)
      unless bibl.call_number.blank?
        if bibl.call_number.match(/^[A-Z]+\s*[0-9]+\s*.*\./)
          authority_value = 'lcc'
        else
          authority_value = 'local'
        end
        xml.mods :classification, bibl.call_number, :authority => authority_value
      end
      
      # Note: We could include various metadata values describing the
      # physical source, but it would be better to develop a separate
      # process that uses the identifiers above to retrieve the entire
      # bibliographic record from the Library catalog, convert it to
      # MODS, and insert it here as the METS <sourceMD>.
      
      # series title
      #unless bibl.series_title.blank?
      #  xml.mods :relatedItem, :type => 'series' do
      #    xml.mods :titleInfo do
      #      xml.mods :title, bibl.series_title
      #    end
      #  end
      #end
      
    end
  end
  private_class_method :mods_source


  #-------------------------------------------------------------------------------
  # Utility methods
  #-------------------------------------------------------------------------------

  # Formats a PID (e.g. "uva-lib:123") for use in ID attribute values within a
  # METS, MODS, etc. document. Replaces colon with underscore by default, or
  # replacement string if passed.
  #
  # A colon in the value of an ID attribute is allowed by the XML
  # specification, but not by the NCName (noncolonized name) datatype used in
  # W3C XML Schema datatypes. Since the METS, MODS, etc. schema are in W3C XML
  # Schema form, using colons in ID attributes produces documents that are
  # well-formed but not valid. To produce valid output, replace the colon.
  def self.format_pid(pid, replacement = '_')
    return pid.gsub(/:/, replacement)
  end
  private_class_method :format_pid
end