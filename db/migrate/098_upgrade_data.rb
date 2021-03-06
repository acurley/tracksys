class UpgradeData < ActiveRecord::Migration
  def change
    
    # Availability Policy 
    #
    # In previous iteration of Tracksys, availabilities were chosen from an
    # enumerated list available in lib/digital_library_availabilities.rb.  In an
    # effort to give users of the application the ability to add or remove 
    # availabilities for digital library objects, this information will now exist
    # in the underlying database and available through the administrative interface.
    #
    # Additionally, the XACML policy URL is going to be stored in the DB rather than 
    # in lib/hydra.rb (or whatever this will be renamed) so it can be manipulated by the 
    # admin user.
    # 
    # Create all appropriate policies and for each policy, associate it with pertinent objects.
    # Legacy objects with this information are:
    # * Bibls
    # * Components
    # * MasterFiles
    # * Units

    say "Reassign old and new availability information."
    Hash[
      "Public" => "http://text.lib.virginia.edu/policy/permit-to-all.xml",
      "VIVA only" => "http://text.lib.virginia.edu/policy/permit-to-viva-only.xml",
      "UVA only" => "http://text.lib.virginia.edu/policy/permit-to-uva-only.xml",
      "Restricted" => "http://text.lib.virginia.edu/policy/deny-to-all.xml"  
    ].each {|policy, url|
      policy_object = AvailabilityPolicy.create!(:name => "#{policy}", :xacml_policy_url => "#{url}")
      update_availability(policy_object.id, policy)
    }

    # Remove unncessary columns.
    # Note: The following cannot be consolidated into their respective change_table methods because an
    # object.availiability_policy_id must exist before the migration can occur.
    remove_column :bibls, :availability
    remove_column :components, :availability
    remove_column :master_files, :availability
    remove_column :units, :availability

    # MasterFile
    #
    # Each MasterFile object will now datetime stamps for:
    # 1. date_archived
    # 2. date_dl_ingest
    # 3. date_dl_update
    #
    # This change gives the model the flexibility now to manage it's own archiving and DL information.  Previously
    # the MasterFile object was required to interrogate it's parent Unit for this information and, at that level,
    # the information was less accurate, representing the information for the batch rather than the individual object.
    #
    # As of this migration, there is no information to populate date_dl_update since that information has not been 
    # recorded heretofore.

    # Update MasterFile.date_archived
    say "Updating master_file.date_archived values"
    Unit.where('date_archived is not null').each {|unit|
      unit.master_files.update_all :date_archived => unit.date_archived
    }

    # Update MasterFile.date_dl_ingest
    say "Updating master_file.date_dl_ingest values"
    Unit.where('date_dl_deliverables_ready').each {|unit|
      unit.master_files.update_all :date_dl_ingest => unit.date_dl_deliverables_ready
      unit.bibl.update_attribute(:date_dl_ingest, unit.date_dl_deliverables_ready)
    }
  end

  # Migrate legacy availability string and turn it into a new legacy object of the same meaning.
  # i.e. master_file.availiability = "Public" becomes 
  # policy = AvailabilityPolicy.where(:name => "Public"); master_file.availability = policy (or master_file.availability_policy_id = policy.id)
  #
  # Note: update_all write a direct SQL UPDATE call and bypasses all validations, callbacks, etc...
  def update_availability(policy_id, old_value)
    classes = ['bibl', 'component', 'master_file', 'unit']
    classes.each {|class_name|
      class_name.classify.constantize.where(:availability => old_value).update_all(:availability_policy_id => policy_id, :availability => nil)
    }
  end
end
