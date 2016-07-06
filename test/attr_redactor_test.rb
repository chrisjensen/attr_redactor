# encoding: UTF-8
require_relative 'test_helper'
class User
  extend AttrRedactor

  redact_hash = {
  	:ssn => :remove,
  	:email => :digest,
  	:medical_notes => :encrypt
  }
  
  encryption_key = 'really, really secure, no one will guess it'
  digest_salt = 'digest salt'

  attr_redactor :data, redact: redact_hash,
  					   encryption_key: encryption_key,
  					   digest_salt: digest_salt
  attr_redactor :attr1, :attr2, redact: redact_hash,
  					   encryption_key: encryption_key,
  					   digest_salt: digest_salt
  attr_redactor :extra, redact: redact_hash,
  					   encryption_key: encryption_key,
  					   digest_salt: digest_salt,
  					   prefix: 'totally_',
  					   suffix: '_secret'
  attr_redactor :secret, redact: redact_hash,
  					   encryption_key: encryption_key,
  					   digest_salt: digest_salt,
  					   attribute: 'renamed_redacted_attribute',
  attr_accessor :name
end

class AlternativeClass
  extend AttrRedactor
 
  redact_hash = { :name => :remove,
  				  :uid => :digest,
  				  :address => :encrypt }
  
  encryption_key = 'a completely different key, equally unguessable'
  digest_salt = 'saltier'

  attr_redactor_options redact: redact_hash,
  						encryption_key: encryption_key,
  						digest_salt: digest_salt
  						
  attr_redactor :secret
end

class SubClass < AlternativeClass
  attr_redactor :testing
end

class SomeOtherClass
  extend AttrEncrypted
  def self.call(object)
    object.class
  end
end

class AttrEncryptedTest < Minitest::Test
  def setup
    @iv = SecureRandom.random_bytes(12)
  end
  
  def data_to_redact
    {
		:ssn => 'my secret ssn',
		:email => 'personal@email.com',
		:medical_notes => 'This is very personal and private'
    }
  end
  
  # Unredacting data will always look slightly different since removed
  # keys will remain removed, and digested will remain digested
  # This hash contains what a structure should look like after redaction
  def unredacted_data
    r = HashRedactor::HashRedactor.new(redact: User.redact_hash,
					   encryption_key: User.encryption_key,
  					   digest_salt: User.digest_salt)

	r.decrypt(r.redact(data_to_redact))
  end

  def test_should_store_datal_in_redacted_attributes
    assert User.redacted_attributes.include?(:data)
  end

  def test_attr_redacted_should_return_true_for_data
    assert User.attr_redacted?('data')
  end

  def test_attr_redacted_should_not_use_the_same_attribute_name_for_two_attributes_in_the_same_line
    refute_equal User.redacted_attributes[:attr1][:attribute], User.redacted_attributes[:attr2][:attribute]
  end

  def test_attr_redacted_should_return_false_for_name
    assert !User.attr_redacted?('name')
  end

  def test_should_generate_redacted_attribute
    assert User.new.respond_to?(:redacted_data)
  end

  def test_should_generate_redacted_attribute_with_a_prefix_and_suffix
    assert User.new.respond_to?(:totally_extra_secret)
  end

  def test_should_generate_an_encrypted_attribute_with_the_attribute_option
    assert User.new.respond_to?(:renamed_redacted_attribute)
  end

  def test_should_not_change_nil_value
    assert_nil User.redact_data(nil, iv: @iv)
  end

  def test_should_redact_data
    refute_nil User.redact_data(data_to_redact)
    refute_equal data_to_redact, User.redact_data(data_to_redact)
  end

  def test_should_use_hash_redactor
    r = HashRedactor::HashRedactor.new(redact: User.redact_hash,
					   encryption_key: User.encryption_key,
  					   digest_salt: User.digest_salt)
    assert_equal r.redact(data_to_redact), User.redact_data(data_to_redact)
  end

  def test_should_redact_when_modifying_the_attr_writer
    @user = User.new
    assert_nil @user.redacted_data
    @user.data = data_to_redact
    refute_nil @user.redacted_data
    assert_equal User.redact_data(data_to_redact), @user.redacted_data
  end

  def test_should_not_unredact_nil_value
    assert_nil User.unredact_data(nil)
  end

  def test_should_unredact
    redacted_data = User.redact_data(data_to_redact)
    refute_equal data_to_redact, redacted_data
    assert_equal r.decrypt(redacted_data), User.unredact_data(redacted_data)
  end

  def test_should_unredact_when_reading
    @user = User.new
    assert_nil @user.data
    @user.redacted_data = User.redact_data(data_to_redact)
    assert_equal unredacted_data, @user.data
  end

  def test_should_redact_when_hash_changed
    @user = User.new
    @user.data = data_to_redact
    old_email_digest = @user.redacted_data[:email_digest]
    @user.data[:email] = 'new_email@example.com'
    refute_equal @user.redacted_data[:email_digest], old_email_digest
  end

  def test_should_use_options_found_in_the_attr_redactor_options_attribute
    @user = AlternativeClass.new
    
    alternative_redact_data = {
		:name => 'Mr Murray',
  		:uid => 124356677,
  		:address => '1 Over the Rainbow, Somewhere'
    }
    
    assert_nil @user.secret
    @user.secret = alternative_redact_data
    refute_nil @user.secret
    
    r = HashRedactor::HashRedactor.new(redact: AlternativeClass.redact_hash,
					   encryption_key: AlternativeClass.encryption_key,
  					   digest_salt: AlternativeClass.digest_salt)

	redacted = r.redact(alternative_redact_data)

    assert_equal redacred, @user.redacted_secret
  end

  def test_should_inherit_encrypted_attributes
    assert_equal [AlternativeClass.redacted_attributes.keys, :testing].flatten.collect { |key| key.to_s }.sort, SubClass.redacted_attributes.keys.collect { |key| key.to_s }.sort
  end

  def test_should_inherit_attr_encrypted_options
    assert !SubClass.attr_redacted_options.empty?
    assert_equal AlternativeClass.attr_redacted_options, Admin.attr_redacted_options
  end

  def test_should_not_inherit_unrelated_attributes
    assert SomeOtherClass.attr_redacted_options.empty?
    assert SomeOtherClass.redacted_attributes.empty?
  end

  def test_should_evaluate_a_symbol_option
    assert_equal SomeOtherClass, SomeOtherClass.new.send(:evaluate_attr_encrypted_option, :class)
  end

  def test_should_evaluate_a_proc_option
    assert_equal SomeOtherClass, SomeOtherClass.new.send(:evaluate_attr_encrypted_option, proc { |object| object.class })
  end

  def test_should_evaluate_a_lambda_option
    assert_equal SomeOtherClass, SomeOtherClass.new.send(:evaluate_attr_encrypted_option, lambda { |object| object.class })
  end

  def test_should_evaluate_a_method_option
    assert_equal SomeOtherClass, SomeOtherClass.new.send(:evaluate_attr_encrypted_option, SomeOtherClass.method(:call))
  end

  def test_should_return_a_string_option
    class_string = 'SomeOtherClass'
    assert_equal class_string, SomeOtherClass.new.send(:evaluate_attr_encrypted_option, class_string)
  end

  def test_should_cast_values_as_strings_before_encrypting
    string_encrypted_email = User.encrypt_email('3', iv: @iv)
    assert_equal string_encrypted_email, User.encrypt_email(3, iv: @iv)
    assert_equal '3', User.decrypt_email(string_encrypted_email, iv: @iv)
  end

  def test_should_create_query_accessor
    @user = User.new
    assert !@user.data?
    @user.data = ''
    assert !@user.data?
    @user.data = data_to_redact
    assert @user.data?
  end

  def test_should_redact_immediately
    @user = User.new
    @user.data = data_to_redact
    assert_equal unredacted_data, @user.data
  end
end
