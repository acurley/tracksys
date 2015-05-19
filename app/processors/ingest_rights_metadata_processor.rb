class IngestRightsMetadataProcessor < ApplicationProcessor
  require 'fedora'
  require 'hydra'

  subscribes_to :ingest_rights_metadata, :ack => 'client', 'activemq.prefetchSize' => 1

  def on_message(message)
    logger.debug 'IngestRightsMetadataProcessor received: ' + message

    # decode JSON message into Ruby hash
    hash = ActiveSupport::JSON.decode(message).symbolize_keys

    # Validate incoming message
    fail "Parameter 'type' is reqiured" if hash[:type].blank?
    fail "Parameter 'type' must equal either 'ingest' or 'update'" unless hash[:type].match('ingest') || hash[:type].match('update')
    fail "Parameter 'object_class' is required" if hash[:object_class].blank?
    fail "Parameter 'object_id' is required" if hash[:object_id].blank?

    @type = hash[:type]
    @object_class = hash[:object_class]
    @object_id = hash[:object_id]
    @object = @object_class.classify.constantize.find(@object_id)
    @messagable_id = hash[:object_id]
    @messagable_type = hash[:object_class]
    @workflow_type = AutomationMessage::WORKFLOW_TYPES_HASH.fetch(self.class.name.demodulize)
    @pid = @object.pid
    instance_variable_set("@#{@object.class.to_s.underscore}_id", @object_id)

    unless @object.exists_in_repo?
      logger.error "ERROR: Object #{@pid} not found in #{FEDORA_REST_URL}"
      Fedora.create_or_update_object(@object, @object.title.to_s)
    end

    # The POLICY datastream should only be posted if the access policy is anything but permit to all.  So exclude this processor's
    # work if @object.availability_policy_id == 1
    if not @object.availability_policy_id == 1
      # Since POLICY is an externally referenced datastream, the xml passed to add_or_update_datastream is empty.
      xml = nil
      dsLocation = Hydra.access(@object)

      # To conform to potentially legacy Fedora requirements, we will create a POLICY datastream.
      Fedora.add_or_update_datastream(xml, @pid, 'POLICY', 'Fedora-required policy datastream', dsLocation: dsLocation, controlGroup: 'R')
      on_success "The POLICY datastream has been created for #{@pid} - #{@object_class} #{@object_id}."
    else
      on_success 'The POLICY datastream was not created because this object is set to Public.'
    end
  end
end
