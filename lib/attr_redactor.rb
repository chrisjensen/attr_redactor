require 'hash_redactor'

# Adds attr_accessors that redact an object's attributes
module AttrRedactor
  autoload :Version, 'attr_redactor/version'

  def self.extended(base) # :nodoc:
    base.class_eval do
      include InstanceMethods
      attr_writer :attr_redactor_options
      @attr_redactor_options, @redacted_attributes = {}, {}
    end
  end

  # Generates attr_accessors that remove, digest or encrypt values in an attribute that is a hash transparently
  #
  # Options
  # Any other options you specify are passed on to hash_redactor which is used for
  # redacting, and in turn onto attr_encrypted which it uses for encryption)
  #
  #   redact:	        Hash that describes the values to redact in the hash. Should be a
  #						map of the form { key => method }, where key is the key to redact
  #						and method is one of :remove, :digest, :encrypt
  #						eg {
  #								:ssn => :remove,
  #								:email => :digest
  #								:medical_notes => :encrypt,
  #						   }
  #
  #   attribute:        The name of the referenced encrypted attribute. For example
  #                     <tt>attr_accessor :data, attribute: :safe_data</tt> would generate 
  #                     an attribute named 'safe_data' to store the redacted data.
  #						This is useful when defining one attribute to encrypt at a time 
  #						or when the :prefix and :suffix options aren't enough.
  #                     Defaults to nil.
  #
  #   prefix:           A prefix used to generate the name of the referenced redacted attributes.
  #                     For example <tt>attr_accessor :data, prefix: 'safe_'</tt> would
  #                     generate attributes named 'safe_data' to store the redacted
  #                     data hash.
  #                     Defaults to 'redacted_'.
  #
  #   suffix:           A suffix used to generate the name of the referenced redacted attributes.
  #                     For example <tt>attr_accessor :data, prefix: '', suffix: '_cleaned'</tt>
  #                     would generate attributes named 'data_cleaned' to store the
  #                     cleaned up data.
  #                     Defaults to ''.
  #
  #   encryption_key:   The encryption key to use for encrypted fields.
  #                     Defaults to nil. Required if you are using encryption.
  #
  #   digest_salt:		The salt to use for digests
  #						Defaults to ""
  #
  #
  # You can specify your own default options
  #
  #   class User
  #     attr_redactor_options.merge!(redact: { :ssn => :remove })
  #     attr_redactor :data
  #   end
  #
  #
  # Example
  #
  #   class User
  #     attr_redactor_options.merge!(encryption_key: 'some secret key')
  #     attr_redactor :data, redact: {
  #								:ssn => :remove,
  #								:email => :digest
  #								:medical_notes => :encrypt,
  #						   }
  #   end
  #
  #   @user = User.new
  #   @user.redacted_data # nil
  #   @user.data? # false
  #   @user.data = { ssn: 'private', email: 'mail@email.com', medical_notes: 'private' }
  #   @user.data? # true
  #   @user.redacted_data # { email_digest: 'XXXXXX', encrypted_medical_notes: 'XXXXXX', encrypted_medical_notes_iv: 'XXXXXXX' }
  #   @user.save!
  #	  @user = User.last
  #
  #   @user.data # { email_digest: 'XXXXXX', medical_notes: 'private' }
  #
  #   See README for more examples
  def attr_redactor(*attributes)
    options = attributes.last.is_a?(Hash) ? attributes.pop : {}
    options = attr_redactor_default_options.dup.merge!(attr_redactor_options).merge!(options)

    attributes.each do |attribute|
      redacted_attribute_name = (options[:attribute] ? options[:attribute] : [options[:prefix], attribute, options[:suffix]].join).to_sym

      instance_methods_as_symbols = attribute_instance_methods_as_symbols
      attr_reader redacted_attribute_name unless instance_methods_as_symbols.include?(redacted_attribute_name)
      attr_writer redacted_attribute_name unless instance_methods_as_symbols.include?(:"#{redacted_attribute_name}=")

	  # Create a redactor for the attribute
	  options[:redactor] = HashRedactor::HashRedactor.new(options)

      define_method(attribute) do
        instance_variable_get("@#{attribute}") || instance_variable_set("@#{attribute}", unredact(attribute, send(redacted_attribute_name)))
      end

      define_method("#{attribute}=") do |value|
        send("#{redacted_attribute_name}=", redact(attribute, value))
        instance_variable_set("@#{attribute}", value)
        # replace with redacted/unredacted value immediately
        instance_variable_set("@#{attribute}", unredact(attribute, send(redacted_attribute_name)))
      end

      define_method("#{attribute}?") do
        value = send(attribute)
        value.respond_to?(:empty?) ? !value.empty? : !!value
      end

      redacted_attributes[attribute.to_sym] = options.merge(attribute: redacted_attribute_name)
    end
  end

  # Default options to use with calls to <tt>attr_redactor</tt>
  #
  # It will inherit existing options from its superclass
  def attr_redactor_options
    @attr_redactor_options ||= superclass.attr_redactor_options.dup
  end

  def attr_redactor_default_options
    {
      prefix:            'redacted_',
      suffix:            '',
      if:                true,
      unless:            false,
      marshal:           false,
      marshaler:         Marshal,
      dump_method:       'dump',
      load_method:       'load',
      mode:              :per_attribute_iv,
    }
  end

  private :attr_redactor_default_options

  # Checks if an attribute is configured with <tt>attr_redactor</tt>
  #
  # Example
  #
  #   class User
  #     attr_accessor :name
  #     attr_redactor :email
  #   end
  #
  #   User.attr_redacted?(:name)  # false
  #   User.attr_redacted?(:email) # true
  def attr_redacted?(attribute)
    redacted_attributes.has_key?(attribute.to_sym)
  end

  # Decrypts values in the attribute specified
  #
  # Example
  #
  #   class User
  #     attr_redactor :data
  #   end
  #
  #   data = User.redact(:data, SOME_REDACTED_HASH)
  def unredact(attribute, redacted_value, options = {})
    options = redacted_attributes[attribute.to_sym].merge(options)
    if options[:if] && !options[:unless] && !redacted_value.nil?
      value = options[:redactor].decrypt(redacted_value, options)
      value
    else
      redacted_value
    end
  end

  # Redacts for the attribute specified
  #
  # Example
  #
  #   class User
  #     attr_redactor :data
  #   end
  #
  #   redacted_data = User.redact(:data, { email: 'test@example.com' })
  def redact(attribute, value, options = {})
    options = redacted_attributes[attribute.to_sym].merge(options)
    if options[:if] && !options[:unless] && !value.nil?
      redacted_value = options[:redactor].redact(value, options)
    else
      value
    end
  end

  # Contains a hash of redacted attributes with virtual attribute names as keys
  # and their corresponding options as values
  #
  # Example
  #
  #   class User
  #     attr_redactor :data, key: 'my secret key'
  #   end
  #
  #   User.redacted_attributes # { data: { attribute: 'redacted_data', encryption_key: 'my secret key' } }
  def redacted_attributes
    @redacted_attributes ||= superclass.redacted_attributes.dup
  end

  # Forwards calls to :redact_#{attribute} or :unredact_#{attribute} to the corresponding redact or unredact method
  # if attribute was configured with attr_redactor
  #
  # Example
  #
  #   class User
  #     attr_redactor :data, key: 'my secret key'
  #   end
  #
  #   User.redact_data('SOME_ENCRYPTED_EMAIL_STRING')
  def method_missing(method, *arguments, &block)
    if method.to_s =~ /^(redact|unredact)_(.+)$/ && attr_redacted?($2)
      send($1, $2, *arguments)
    else
      super
    end
  end

  module InstanceMethods
    # Decrypts a value for the attribute specified using options evaluated in the current object's scope
    #
    # Example
    #
    #  class User
    #    attr_accessor :secret_key
    #    attr_redactor :data, key: :secret_key
    #
    #    def initialize(secret_key)
    #      self.secret_key = secret_key
    #    end
    #  end
    #
    #  @user = User.new('some-secret-key')
    #  @user.unredact(:data, SOME_REDACTED_HASH)
    def unredact(attribute, redacted_value)
      redacted_attributes[attribute.to_sym][:operation] = :unredacting
      self.class.unredact(attribute, redacted_value, evaluated_attr_redacted_options_for(attribute))
    end

    # Redacts a value for the attribute specified using options evaluated in the current object's scope
    #
    # Example
    #
    #  class User
    #    attr_accessor :secret_key
    #    attr_redactor :data, key: :secret_key
    #
    #    def initialize(secret_key)
    #      self.secret_key = secret_key
    #    end
    #  end
    #
    #  @user = User.new('some-secret-key')
    #  @user.redact(:data, 'test@example.com')
    def redact(attribute, value)
      redacted_attributes[attribute.to_sym][:operation] = :redacting
      self.class.redact(attribute, value, evaluated_attr_redacted_options_for(attribute))
    end

    # Copies the class level hash of redacted attributes with virtual attribute names as keys
    # and their corresponding options as values to the instance
    #
    def redacted_attributes
      @redacted_attributes ||= self.class.redacted_attributes.dup
    end

    protected

      # Returns attr_redactor options evaluated in the current object's scope for the attribute specified
      def evaluated_attr_redacted_options_for(attribute)
        evaluated_options = Hash.new
        attribute_option_value = redacted_attributes[attribute.to_sym][:attribute]
        redacted_attributes[attribute.to_sym].map do |option, value|
          evaluated_options[option] = evaluate_attr_redactor_option(value)
        end

        evaluated_options[:attribute] = attribute_option_value

        evaluated_options
      end

      # Evaluates symbol (method reference) or proc (responds to call) options
      #
      # If the option is not a symbol or proc then the original option is returned
      def evaluate_attr_redactor_option(option)
        if option.is_a?(Symbol) && respond_to?(option)
          send(option)
        elsif option.respond_to?(:call)
          option.call(self)
        else
          option
        end
      end
  end

  protected

  def attribute_instance_methods_as_symbols
    instance_methods.collect { |method| method.to_sym }
  end

end


Dir[File.join(File.dirname(__FILE__), 'attr_redactor', 'adapters', '*.rb')].each { |adapter| require adapter }
