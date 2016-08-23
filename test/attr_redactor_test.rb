# encoding: UTF-8
require_relative 'test_helper'
class User
  extend AttrRedactor

  def self.redaction_hash
    {
  	  :ssn => :remove,
      :email => :digest,
  	  :medical_notes => :encrypt
    }
  end
  
  def self.encryption_key
   'really, really secure, no one will guess it'
  end
  
  def self.digest_salt
    'digest salt'
  end

  attr_redactor :data, redact: redaction_hash,
  					   encryption_key: encryption_key,
  					   digest_salt: digest_salt
  attr_redactor :attr1, :attr2, redact: redaction_hash,
  					   encryption_key: encryption_key,
  					   digest_salt: digest_salt
  attr_redactor :extra, redact: redaction_hash,
  					   encryption_key: encryption_key,
  					   digest_salt: digest_salt,
  					   prefix: 'totally_',
  					   suffix: '_secret'
  attr_redactor :secret, redact: redaction_hash,
  					   encryption_key: encryption_key,
  					   digest_salt: digest_salt,
  					   attribute: 'renamed_redacted_attribute'
  attr_accessor :name
end

class AlternativeClass
  extend AttrRedactor
 
  def self.redaction_hash
    {
       :name => :remove,
  	   :uid => :digest,
  	   :address => :encrypt
    }
  end
  
  def self.encryption_key
   'a completely different key, equally unguessable'
  end
  
  def self.digest_salt
   'saltier'
  end

  attr_redactor_options.merge! redact: redaction_hash,
  						encryption_key: encryption_key,
  						digest_salt: digest_salt
  						
  attr_redactor :secret
end

class Post
  extend AttrRedactor
  
  attr_redactor :post_info, :redact => :redact_hash,
  					   encryption_key: 'encryption_key is super long and unguessable',
  					   digest_salt: 'pink himalayan'
  
  attr_accessor :redact_hash
end

class SubClass < AlternativeClass
  attr_redactor :testing
end

class SomeOtherClass
  extend AttrRedactor
  
  def self.call(object)
    object.class
  end
end

class AttrRedactorTest < Minitest::Test
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
  
  def assert_redacted_hashes_equiv(hash1, hash2, redact)
    # Since encryption uses a new iv each time, they cannot be compared
    # only tested for presence
    keys = redact.select{ |key,method| method == :encrypt }.keys
    uncomparable_keys = keys.map{ |key| [ :"encrypted_#{key}", :"encrypted_#{key}_iv" ] }.flatten
  
    h1 = hash1.select{ |key, value| !uncomparable_keys.include?(key) }
	h2 = hash2.select{ |key, value| !uncomparable_keys.include?(key) }
	
	assert_equal h1, h2
	uncomparable_keys.each do |key|
	  assert hash1.has_key? key
	  assert hash2.has_key? key
	end
  end
  
  # Unredacting data will always look slightly different since removed
  # keys will remain removed, and digested will remain digested
  # This hash contains what a structure should look like after redaction
  def unredacted_data
    r = HashRedactor::HashRedactor.new(redact: User.redaction_hash,
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
  
  def test_attr_redacted_has_attr_redact_hash_attribute
    expected_hash = {
			  :ssn => :remove,
			  :email => :digest,
			  :medical_notes => :encrypt
    		}
  
    assert expected_hash, User.new.data_redact_hash
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

  def test_should_generate_redacted_attribute_with_the_attribute_option
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
    r = HashRedactor::HashRedactor.new(redact: User.redaction_hash,
					   encryption_key: User.encryption_key,
  					   digest_salt: User.digest_salt)
  					   
    assert_redacted_hashes_equiv r.redact(data_to_redact),
    					 User.redact_data(data_to_redact), 
    					 User.redaction_hash
  end

  def test_should_redact_when_modifying_the_attr_writer
    @user = User.new
    assert_nil @user.redacted_data
    @user.data = data_to_redact
    refute_nil @user.redacted_data
    assert_redacted_hashes_equiv User.redact_data(data_to_redact),
    					 @user.redacted_data,
    					 User.redaction_hash
  end

  def test_should_not_unredact_nil_value
    assert_nil User.unredact_data(nil)
  end

  def test_should_unredact
    r = HashRedactor::HashRedactor.new(redact: User.redaction_hash,
					   encryption_key: User.encryption_key,
  					   digest_salt: User.digest_salt)

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
    
    r = HashRedactor::HashRedactor.new(redact: AlternativeClass.redaction_hash,
					   encryption_key: AlternativeClass.encryption_key,
  					   digest_salt: AlternativeClass.digest_salt)

	redacted = r.redact(alternative_redact_data)

	assert_redacted_hashes_equiv(redacted, @user.redacted_secret, 
					AlternativeClass.redaction_hash)
  end

  def test_should_inherit_redacted_attributes
    assert_equal [AlternativeClass.redacted_attributes.keys, :testing].flatten.collect { |key| key.to_s }.sort, SubClass.redacted_attributes.keys.collect { |key| key.to_s }.sort
  end

  def test_should_inherit_attr_redactor_options
    assert !SubClass.attr_redactor_options.empty?
    assert_equal AlternativeClass.attr_redactor_options, SubClass.attr_redactor_options
  end

  def test_should_not_inherit_unrelated_attributes
    assert SomeOtherClass.attr_redactor_options.empty?
    assert SomeOtherClass.redacted_attributes.empty?
  end

  def test_should_evaluate_a_symbol_option
    assert_equal SomeOtherClass, SomeOtherClass.new.send(:evaluate_attr_redactor_option, :class)
  end

  def test_should_evaluate_a_proc_option
    assert_equal SomeOtherClass, SomeOtherClass.new.send(:evaluate_attr_redactor_option, proc { |object| object.class })
  end

  def test_should_evaluate_a_lambda_option
    assert_equal SomeOtherClass, SomeOtherClass.new.send(:evaluate_attr_redactor_option, lambda { |object| object.class })
  end

  def test_should_evaluate_a_method_option
    assert_equal SomeOtherClass, SomeOtherClass.new.send(:evaluate_attr_redactor_option, SomeOtherClass.method(:call))
  end

  def test_should_return_a_string_option
    class_string = 'SomeOtherClass'
    assert_equal class_string, SomeOtherClass.new.send(:evaluate_attr_redactor_option, class_string)
  end

  def test_should_create_query_accessor
    @user = User.new
    assert !@user.data?
    @user.data = data_to_redact
    assert @user.data?
  end

  def test_should_redact_immediately
    @user = User.new
    @user.data = data_to_redact
    assert_equal unredacted_data, @user.data
  end
  
  def test_redact_hash_from_function
    post_data = { :followers => 'macy, george', :critics => 'Barbados Glum',
    		:bio => 'A strange, quiet man' }

    redact_hash1 = {
    	:followers => :remove,
    	:critics => :encrypt,
    	:bio => :digest
    }

    redact_hash2 = {
    	:followers => :keep,
    	:critics => :digest,
    	:bio => :encrypt
    }

	post = Post.new
	post.redact_hash = redact_hash1
	post.post_info = post_data
	
	post2 = Post.new
	post2.redact_hash = redact_hash2
	post2.post_info = post_data

	refute post.redacted_post_info.has_key? :followers
	assert post.redacted_post_info.has_key? :encrypted_critics
	assert post.redacted_post_info.has_key? :bio_digest

	assert post2.redacted_post_info.has_key? :followers
	assert post2.redacted_post_info.has_key? :critics_digest
	assert post2.redacted_post_info.has_key? :encrypted_bio
  end
end
