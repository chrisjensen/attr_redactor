require_relative 'test_helper'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')

def create_tables
  silence_stream(STDOUT) do
    ActiveRecord::Schema.define(version: 1) do
      create_table :people do |t|
        t.string   :redacted_data
        t.string :login
        t.boolean :is_admin
      end
    end
  end
end

# The table needs to exist before defining the class
create_tables

ActiveRecord::MissingAttributeError = ActiveModel::MissingAttributeError unless defined?(ActiveRecord::MissingAttributeError)

if ::ActiveRecord::VERSION::STRING > "4.0"
  module Rack
    module Test
      class UploadedFile; end
    end
  end

  require 'action_controller/metal/strong_parameters'
end

class Person < ActiveRecord::Base
  self.attr_redactor_options[:encryption_key] = "a very very very long secure, very secure key"
  self.attr_redactor_options[:redact] = {
	:ssn => :remove,
	:email => :digest,
	:history => :encrypt
  }
  
  serialize :redacted_data, Hash
  attr_redactor :data

  attr_protected :login if ::ActiveRecord::VERSION::STRING < "4.0"
end

class PersonWithValidation < Person
  validates_presence_of :data
end

class ActiveRecordTest < Minitest::Test

  def setup
    ActiveRecord::Base.connection.tables.each { |table| ActiveRecord::Base.connection.drop_table(table) }
    create_tables
  end

  def test_should_marshal_and_redact_data
    @person = Person.create :data => { :ssn => '12345', :email => 'some@address.com',
    			 :history => 'A big secret' }
    refute_nil @person.redacted_data
    refute_equal @person.data, @person.redacted_data
    assert_equal @person.data, Person.first.data
  end

  def test_should_validate_presence_of_data
    @person = PersonWithValidation.new
    assert !@person.valid?
    assert !@person.errors[:data].empty? || @person.errors.on(:data)
  end

  def test_should_create_changed_predicate
    data_to_redact = { :ssn => '12345', :email => 'some@address.com',
    			 :history => 'A big secret' }
    alternate_data = { :ssn => '54321', :email => 'some@address.com',
    			 :history => 'A really big secret' }
  
    person = Person.create!(data: data_to_redact)
    refute person.data_changed?
    person.data = data_to_redact
    refute person.data_changed?
    person.data = alternate_data
    assert person.data_changed?
    person.save!
    person.data = alternate_data
    refute person.data_changed?
    person.data = nil
    assert person.data_changed?
  end

  def test_should_create_was_predicate
    data_to_redact = { :ssn => '12345', :email => 'some@address.com',
    			 :history => 'A big secret' }

    person = Person.create!(data: data_to_redact)
    assert_equal data_to_redact[:history], person.data[:history]
  end

  if ::ActiveRecord::VERSION::STRING > "4.0"
    def test_should_assign_attributes
      @user = Person.new(login: 'login', is_admin: false)
      @user.attributes = ActionController::Parameters.new(login: 'modified', is_admin: true).permit(:login)
      assert_equal 'modified', @user.login
    end

    def test_should_not_assign_protected_attributes
      @user = Person.new(login: 'login', is_admin: false)
      @user.attributes = ActionController::Parameters.new(login: 'modified', is_admin: true).permit(:login)
      assert !@user.is_admin?
    end

    def test_should_raise_exception_if_not_permitted
      @user = Person.new(login: 'login', is_admin: false)
      assert_raises ActiveModel::ForbiddenAttributesError do
        @user.attributes = ActionController::Parameters.new(login: 'modified', is_admin: true)
      end
    end

    def test_should_raise_exception_on_init_if_not_permitted
      assert_raises ActiveModel::ForbiddenAttributesError do
        @user = Person.new ActionController::Parameters.new(login: 'modified', is_admin: true)
      end
    end
  else
    def test_should_assign_attributes
      @user = Person.new(login: 'login', is_admin: false)
      @user.attributes = { login: 'modified', is_admin: true }
      assert @user.is_admin
    end

    def test_should_not_assign_protected_attributes
      @user = Person.new(login: 'login', is_admin: false)
      @user.attributes = { login: 'modified', is_admin: true }
      assert_nil @user.login
    end

    def test_should_assign_protected_attributes
      @user = Person.new(login: 'login', is_admin: false)
      if ::ActiveRecord::VERSION::STRING > "3.1"
        @user.send(:assign_attributes, { login: 'modified', is_admin: true }, without_protection: true)
      else
        @user.send(:attributes=, { login: 'modified', is_admin: true }, false)
      end
      assert_equal 'modified', @user.login
    end
  end

  def test_should_allow_assignment_of_nil_attributes
    @person = Person.new
    assert_nil(@person.attributes = nil)
  end

  if ::ActiveRecord::VERSION::STRING > "3.1"
    def test_should_allow_assign_attributes_with_nil
      @person = Person.new
      assert_nil(@person.assign_attributes nil)
    end
  end

  # See https://github.com/attr-encrypted/attr_encrypted/issues/68
  def test_should_invalidate_virtual_attributes_on_reload
    old_data = { :history => 'Itself' }
    new_data = { :history => 'Repeating itself' }
    p = Person.create!(data: old_data)
    assert_equal p.data[:history], old_data[:history]
    p.data = new_data
    assert_equal p.data[:history], new_data[:history]

    result = p.reload
    assert_equal p, result
    assert_equal p.data[:history], old_data[:history]
  end
end
