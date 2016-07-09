if defined?(ActiveRecord::Base)
  module AttrRedactor
    module Adapters
      module ActiveRecord
        def self.extended(base) # :nodoc:
          base.class_eval do

            # https://github.com/attr-encrypted/attr_encrypted/issues/68
            alias_method :reload_without_attr_redactor, :reload
            def reload(*args, &block)
              result = reload_without_attr_redactor(*args, &block)
              self.class.redacted_attributes.keys.each do |attribute_name|
                instance_variable_set("@#{attribute_name}", nil)
              end
              result
            end

            def perform_attribute_assignment(method, new_attributes, *args)
              return if new_attributes.blank?

              send method, new_attributes.reject { |k, _|  self.class.redacted_attributes.key?(k.to_sym) }, *args
              send method, new_attributes.reject { |k, _| !self.class.redacted_attributes.key?(k.to_sym) }, *args
            end
            private :perform_attribute_assignment

            if ::ActiveRecord::VERSION::STRING > "3.1"
              alias_method :assign_attributes_without_attr_redactor, :assign_attributes
              def assign_attributes(*args)
                perform_attribute_assignment :assign_attributes_without_attr_redactor, *args
              end
            end

            alias_method :attributes_without_attr_redactor=, :attributes=
            def attributes=(*args)
              perform_attribute_assignment :attributes_without_attr_redactor=, *args
            end
          end
        end

        protected

          # <tt>attr_redactor</tt> method
          def attr_redactor(*attrs)
            super
            options = attrs.extract_options!
            attr = attrs.pop
            options.merge! redacted_attributes[attr]

            define_method("#{attr}_changed?") do
              send(attr) != send("#{attr}_was")
            end

            define_method("#{attr}_was") do
              attr_was_options = { operation: :unredacting }
              redacted_attributes[attr].merge!(attr_was_options)
              evaluated_options = evaluated_attr_redacted_options_for(attr)
              [:iv, :salt, :operation].each { |key| redacted_attributes[attr].delete(key) }
              self.class.unredact(attr, send("#{options[:attribute]}_was"), evaluated_options)
            end

            alias_method "#{attr}_before_type_cast", attr
          end

          def attribute_instance_methods_as_symbols
            # We add accessor methods of the db columns to the list of instance
            # methods returned to let ActiveRecord define the accessor methods
            # for the db columns

            # Use with_connection so the connection doesn't stay pinned to the thread.
            connected = ::ActiveRecord::Base.connection_pool.with_connection(&:active?) rescue false

            if connected && table_exists?
              columns_hash.keys.inject(super) {|instance_methods, column_name| instance_methods.concat [column_name.to_sym, :"#{column_name}="]}
            else
              super
            end
          end
      end
    end
  end

  ActiveRecord::Base.extend AttrRedactor
  ActiveRecord::Base.extend AttrRedactor::Adapters::ActiveRecord
end
