if defined?(DataMapper)
  module AttrRedactor
    module Adapters
      module DataMapper
        def self.extended(base) # :nodoc:
          class << base
            alias_method :included_without_attr_redactor, :included
            alias_method :included, :included_with_attr_redactor
          end
        end

        def included_with_attr_redactor(base)
          included_without_attr_redactor(base)
          base.extend AttrRedactor
        end
      end
    end
  end

  DataMapper::Resource.extend AttrRedactor::Adapters::DataMapper
end