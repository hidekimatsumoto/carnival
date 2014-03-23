# -*- encoding : utf-8 -*-
module Carnival
  class BaseAdminPresenter
    include Rails.application.routes.url_helpers
    attr_accessor :special_scope_to_exec

    def initialize(params)
      @@controller = params[:controller]
      @special_scopes_to_exec = nil
    end

    def base_query
      @base_query
    end

    #New implementation starts here
    @@actions = {}
    def self.action(name, params = {})
      @@actions[presenter_class_name] = {} if @@actions[presenter_class_name].nil?
      @@actions[presenter_class_name][name] = Carnival::Action.new(self.new({}), name, params)
    end

    def actions
      @@actions[presenter_class_name]
    end

    def actions_for_record
      filter_actions([:show, :edit, :destroy], :record)
    end

    def actions_for_page
      filter_actions([:new], :page)
    end

    def has_action?(action)
      @@actions[presenter_class_name].present? && @@actions[presenter_class_name][action].present?
    end

    @@fields = {}
    @@scopes = {}
    @@forms = {}

    def self.scope(name, params = {})
      self.instantiate_element(@@scopes, Carnival::Scope, name, params)
    end

    def self.field(name, params = {})
      self.instantiate_element(@@fields, Carnival::Field, name, params)
    end

    def self.form(action, params = {})
      self.instantiate_element(@@forms, Carnival::Form, name, params)
    end

    def scopes
      @@scopes[presenter_class_name]
    end

    def scopes_counters
      scopes = {}
      if @@scopes[presenter_class_name].present?
        @@scopes[presenter_class_name].each do |key, scope|
          if base_query.present?
            scopes[scope.name] = base_query.send(scope.name).count
          else
            scopes[scope.name] = model_class.send(scope.name).count
          end
        end
      end
      scopes
    end

    def fields
      @@fields[presenter_class_name]
    end

    def fields_for_action(action)
      fields_action = {}
      @@fields[presenter_class_name].each do |key, field|
        if field.valid_for_action?(action)
          fields_action[key] = field
        end
      end
      fields_action
    end

    def form_for(action)
      form = Carnival::Form.new(action)
      form =  @@forms[presenter_class_name][action] if @@forms[presenter_class_name].present? and  @@forms[presenter_class_name][action].present?
      form.fields = fields_for_action(action)
      form
    end

    def model_name
      self.class.to_s.split("::").last().gsub("Presenter", "").underscore
    end

    def model_path(action, extra_params=nil)
      params = {controller: model_class.to_s.pluralize.underscore, action: action}
      params = params.merge(extra_params) if extra_params.present?
      params = params.merge(:only_path => true)
      url_for(params)
    end

    def full_model_name
      self.class.to_s.gsub("Presenter", "").underscore
    end

    def controller_name
      @@controller.controller_name
    end

    def table_name
      model_name.pluralize
    end

    def searchable_fields
      searchable_fields = {}
      @@fields[presenter_class_name].each do |key, field|
        searchable_fields[key] = field if field.searchable?
      end
      searchable_fields
    end

    def default_scope
      default_scope = nil
      @@scopes[presenter_class_name].each do |key, scope|
        default_scope = scope if scope.default?
        break
      end
      default_scope = @@scopes[presenter_class_name].first[1] if default_scope.nil?
      default_scope
    end

    def default_sortable_field
      default_field = nil
      @@fields[presenter_class_name].each do |key, field|
        default_field = field if field.default_sortable?
        break
      end
      default_field = @@fields[presenter_class_name].first[1] if default_field.nil?
      default_field
    end

    def default_sort_direction
      default_sortable_field.default_sort_direction
    end

    def sortable_fields
      sortable_fields = {}
      @@fields[presenter_class_name].each do |key, field|
        sortable_fields[key] = field if field.sortable?
      end
      sortable_fields
    end

    def advanced_search_fields
      advanced_search_fields = {}
      @@fields[presenter_class_name].each do |key, field|
        advanced_search_fields[key] = field if field.advanced_searchable?
      end
      advanced_search_fields
    end

    def date_filter_field
      date_field = nil
      @@fields[presenter_class_name].each do |key, field|
        if field.date_filter?
          date_field = field
          break
        end
      end
      date_field
    end

    def model_class
      self.class.to_s.gsub("Presenter", "").constantize
    end

    def relation_field?(field)
      if model_class.reflect_on_association(field)
        true
      else
        false
      end
    end

    def relation_label(field, record)
      if relation_field?(field)
        if model_class.reflect_on_association(field).macro == :belongs_to
          return record.send(field)
        else
          return I18n.t("#{model_name}.#{field}")
        end
      end
      raise
      return ""
    end

    def relation_path(field, record)
      if relation_field?(field)
        related_class = model_class.reflect_on_association(field).klass.name.pluralize.underscore
        if model_class.reflect_on_association(field).macro == :belongs_to
          params = {:controller => related_class, :action => :show, :id => record.send(model_class.reflect_on_association(field).foreign_key)}
        else
          params = {:controller => related_class, :action => :index, :advanced_search => make_relation_advanced_query_url_options(field, record)}
        end
        params = params.merge(:only_path => true)
        return url_for(params)
      end
      return nil
    end

    def parse_advanced_search records, search_syntax
      search = JSON.parse(search_syntax)
      search.keys.each do |key|
        search_field = key
        search_field = key.split(".").last if key.include?(".")
        search_field = search_field.gsub("_id", "") if search_field.ends_with?("_id")
        if @@fields[presenter_class_name].keys.include? search_field.to_sym
          if @@fields[presenter_class_name][search_field.to_sym].advanced_searchable?
            records =  parse_advanced_search_field(search_field, search[key], records)
          end
        end
      end
      records
    end

    protected
    def make_relation_advanced_query_url_options(field, record)
      relation_model = model_class.reflect_on_association(field).klass.name.pluralize.underscore.split("/").last
      relation_field = model_class.reflect_on_association(field).foreign_key
      relation_value = record.id
      {"#{relation_model}.#{relation_field}" => relation_value}
    end

    def filter_actions(default_actions, target)
      actions = {}
      if @@actions[presenter_class_name]
        @@actions[presenter_class_name].each do |key, action|
          if default_actions.include?(key) || action.target == target
            actions[key] = action
          end
        end
      end
      actions
    end

    def self.presenter_class_name
      if self.class.name == "Class"
        self.to_s
      else
        self.class.name
      end
    end

    def presenter_class_name
      if self.class.name == "Class"
        self.to_s
      else
        self.class.name
      end
    end

    def parse_advanced_search_field search_field, field_param, records
      return records if not field_param["value"].present?
      return records if field_param["value"] == ""

      if relation_field?(search_field.to_sym)
        related_model = model_class.reflect_on_association(search_field.to_sym).klass.name.underscore
        foreign_key = model_class.reflect_on_association(search_field.to_sym).foreign_key
        if model_class.reflect_on_association(search_field.to_sym).macro == :belongs_to
          records = records.joins(related_model.split("/").last.to_sym)
        else
          records = records.joins(related_model.split("/").last.pluralize)
        end
        table = related_model.split("/").last.pluralize
        column = "id"
      else
        table = table_name
        column = search_field
      end
      full_column_query = "#{table}.#{column}"
      where_clause = nil

      case field_param["operator"]
        when "equal"
          if field_param["value"] == "nil"
            where_clause = "#{full_column_query} is null"
          else
            where_clause = "#{full_column_query} = #{advanced_search_field_value_for_query(field_param["value"])}"
          end
        when "like"
          where_clause = "#{full_column_query} like '%#{field_param["value"]}%'"
        when "greater_than"
          where_clause = "#{full_column_query} >= '#{field_param["value"]}'"
        when "less_than"
          where_clause = "#{full_column_query} <= '#{field_param["value"]}'"
        when "between"
          where_clause = "#{full_column_query} between '#{field_param["value"]}' and '#{field_param["value2"]}'"
        else
          where_clause = "#{full_column_query} = #{advanced_search_field_value_for_query(field_param["value"])}"
      end
      records = records.where(where_clause) if where_clause.present?
      records
    end

    def advanced_search_field_value_for_query(value)
      if "true" == value.downcase
        return "'t'"
      elsif "false" == value.downcase
        return "'f'"
      else
        '#{value}'
      end
    end

    def self.instantiate_element(container, klass, name, params)
      container[presenter_class_name] = {} if container[presenter_class_name].nil?
      container[presenter_class_name][name] = klass.new(name, params)
    end
  end
end