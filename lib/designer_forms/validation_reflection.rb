# Version 1.4
# Jeremy: added requires? and field_validates_with methods
# Jeremy: restructured the naming structure to allow for integration with
#         factory standard structure.

require 'active_record/reflection'

module DesignerForms # :nodoc:
  module ActiveRecordExtensions # :nodoc:
    module ValidationReflection # :nodoc:

      # TODO: move into core configuration for plugin
      CONFIG_PATH = File.join(RAILS_ROOT, 'config', 'plugins', 'validation_reflection.rb')
      
      mattr_accessor :reflected_validations
      DesignerForms::ActiveRecordExtensions::ValidationReflection.reflected_validations = %w(
        validates_acceptance_of
        validates_associated
        validates_confirmation_of
        validates_exclusion_of
        validates_format_of
        validates_inclusion_of
        validates_length_of
        validates_numericality_of
        validates_presence_of
        validates_uniqueness_of
      )

      mattr_accessor :in_ignored_subvalidation
      DesignerForms::ActiveRecordExtensions::ValidationReflection.in_ignored_subvalidation = false
      
      def self.included(base)
        return if base.kind_of?(DesignerForms::ActiveRecordExtensions::ValidationReflection::ClassMethods)
        base.extend(ClassMethods)
      end

      def self.load_config
        if File.file?(CONFIG_PATH)
          config = OpenStruct.new
          config.reflected_validations = reflected_validations
          silence_warnings do
            eval(IO.read(CONFIG_PATH), binding, CONFIG_PATH)
          end
        end
      end

      def self.install(base)
        reflected_validations.freeze
        reflected_validations.each do |validation_type|
          ignore_subvalidations = false
          if validation_type.kind_of?(Hash)
            ignore_subvalidations = validation_type[:ignore_subvalidations]
            validation_type = validation_type[:method]
          end
          base.class_eval <<-"end_eval"
            class << self
              def #{validation_type}_with_reflection(*attr_names)
                ignoring_subvalidations(#{ignore_subvalidations}) do
                  #{validation_type}_without_reflection(*attr_names)
                  remember_validation_metadata(:#{validation_type}, *attr_names)
                end
              end

              alias_method_chain :#{validation_type}, :reflection
            end
          end_eval
        end
      end

      module ClassMethods

        # Returns an array of MacroReflection objects for all validations in the class
        def reflect_on_all_validations
          read_inheritable_attribute(:validations) || []
        end

        # Returns an array of MacroReflection objects for all validations defined for the field +attr_name+.
        def reflect_on_validations_for(attr_name)
          attr_name = attr_name.to_sym
          reflect_on_all_validations.select do |reflection|
            reflection.name == attr_name
          end
        end

        # Checks to see if various validation methods that equate to "required" are is defined for the field +attr_name+.
        def requires?(attr_name)
          attr_name = attr_name.to_sym
          validator_macros = reflect_on_validations_for(attr_name)
          validators = validator_macros.collect{ |validator| validator = validator.macro }

          if validators.include?(:validates_length_of)
            validator_macros.each do |validator|
              if validator.macro == :validates_length_of &&
                 (!validator.options.empty? && validator.options[:allow_blank] == false ||
                 (validator.options[:minimum] && validator.options[:allow_blank] != true))
                return true;
              end
            end
          end
          validators.include?(:validates_presence_of) || validators.include?(:validates_acceptance_of) || validators.include?(:validates_confirmation_of)
        end

        
        # Returns a boolean based on if the +attr_name+ field validates with the given +validation_method+.
        def field_validates_with(attr_name, validation_method)
          attr_name = attr_name.to_sym
          validation_method = validation_method.to_sym
          reflect_on_validations_for(attr_name).collect{ |validator| validator = validator.macro }.include?(validation_method)
        end

        private
        
        def remember_validation_metadata(validation_type, *attr_names)
          configuration = attr_names.last.is_a?(Hash) ? attr_names.pop : {}
          attr_names.each do |attr_name|
            write_inheritable_array :validations,
              [ ActiveRecord::Reflection::MacroReflection.new(validation_type, attr_name.to_sym, configuration, self) ]
          end
        end
        
        def ignoring_subvalidations(ignore)
          save_ignore = DesignerForms::ActiveRecordExtensions::ValidationReflection.in_ignored_subvalidation
          unless DesignerForms::ActiveRecordExtensions::ValidationReflection.in_ignored_subvalidation
            DesignerForms::ActiveRecordExtensions::ValidationReflection.in_ignored_subvalidation = ignore
            yield
          end
        ensure
          DesignerForms::ActiveRecordExtensions::ValidationReflection.in_ignored_subvalidation = save_ignore
        end
      end

    end
  end
end