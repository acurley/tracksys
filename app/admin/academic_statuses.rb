ActiveAdmin.register AcademicStatus do
  menu :parent => "Miscellaneous"
  config.sort_order = 'name_asc'

  filter :id
  filter :name

  actions :all, :except => [:destroy]

  scope :all, :default => true

  index do
    column :name
    column :customers do |academic_status|
      link_to "#{academic_status.customers_count.to_s}", admin_customers_path(:q => {:academic_status_id_eq => academic_status.id})
    end
    column :requests do |academic_status|
      link_to "#{academic_status.requests.size.to_s}", admin_orders_path(:q => {:academic_status_id_eq => academic_status.id}, :scope => 'awaiting_approval')
    end
    column :orders do |academic_status|
      link_to "#{academic_status.orders.size.to_s}", admin_orders_path(:q => {:academic_status_id_eq => academic_status.id}, :scope => 'approved')
    end
    column :units do |academic_status|
      link_to "#{academic_status.units.size.to_s}", admin_units_path(:q => {:academic_status_id_eq => academic_status.id})
    end
    column :master_files do |academic_status|
      link_to "#{academic_status.master_files.size.to_s}", admin_master_files_path(:q => {:academic_status_id_eq => academic_status.id})
    end
    column :created_at do |academic_status|
      format_date(academic_status.created_at)
    end
    column :updated_at do |academic_status|
      format_date(academic_status.updated_at)
    end
    column("") do |academic_status|
      div do
        link_to "Details", resource_path(academic_status), :class => "member_link view_link"
      end
      div do
        link_to I18n.t('active_admin.edit'), edit_resource_path(academic_status), :class => "member_link edit_link"
      end
    end
  end 

  show do
    panel "Detailed Information" do
      attributes_table_for academic_status do
        row :name
        row :created_at do |academic_status|
          format_date(academic_status.created_at)
        end
        row :updated_at do |academic_status|
          format_date(academic_status.updated_at)
        end
      end
    end
  end

  sidebar "Related Information", :only => :show do
    attributes_table_for academic_status do
      row :customers do |academic_status|
        link_to "#{academic_status.customers_count.to_s}", admin_customers_path(:q => {:academic_status_id_eq => academic_status.id})
      end
      row :requests do |academic_status|
        link_to "#{academic_status.requests.size.to_s}", admin_orders_path(:q => {:academic_status_id_eq => academic_status.id}, :scope => 'awaiting_approval')
      end
      row :orders do |academic_status|
        link_to "#{academic_status.orders.size.to_s}", admin_orders_path(:q => {:academic_status_id_eq => academic_status.id}, :scope => 'approved')
      end
      row :units do |academic_status|
        link_to "#{academic_status.units.size.to_s}", admin_units_path(:q => {:academic_status_id_eq => academic_status.id})
      end
      row :master_files do |academic_status|
        link_to "#{academic_status.master_files.size.to_s}", admin_master_files_path(:q => {:academic_status_id_eq => academic_status.id})
      end
    end
  end

  sidebar "Orders Complete By Year", :only => :show do
    attributes_table_for academic_status do
      row("2012") {|academic_status| academic_status.orders.where(:date_archiving_complete => '2012-01-01'..'2012-12-31').count }
      row("2011") {|academic_status| academic_status.orders.where(:date_archiving_complete => '2011-01-01'..'2011-12-31').count }
      row("2010") {|academic_status| academic_status.orders.where(:date_archiving_complete => '2010-01-01'..'2010-12-31').count }
      row("2009") {|academic_status| academic_status.orders.where(:date_archiving_complete => '2009-01-01'..'2009-12-31').count }
    end
  end
  
end
