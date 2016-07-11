# attr_redactor

Generates attr_accessors that transparently redact a hash attribute by removing, digesting or encrypting certain keys.

This code is based off of the [attr_encrypted/attr_encrypted](https://github.com/attr-encrypted/attr_encrypted) code base.

Helper classes for `ActiveRecord`, 

`DataMapper`, and `Sequel` helpers have been retained, but have not been successfully tested.

## Installation

Add attr_redactor to your gemfile:

```ruby
  gem "attr_redactor"
```

Then install the gem:

```bash
  bundle install
```

## Usage

If you're using an ORM like `ActiveRecord` using attr_redactor is easy:

```ruby
  class User
    attr_redactor :user_data, redact: { :ssn => :remove, :email => :encrypt }
  end
```

If you're using a PORO, you have to do a little bit more work by extending the class:

```ruby
  class User
    extend AttrRedactor
    attr_accessor :name
    attr_redactor :user_data, redact: { :ssn => :remove, :email => :encrypt }

    def load
      # loads the stored data
    end

    def save
      # saves the :name and :redacted_user_data attributes somewhere (e.g. filesystem, database, etc)
    end
  end

  user = User.new
  user.user_data = { ssn: '123-45-6789', email: 'personal@email.com' }
  user.redacted_data[:encrypted_email] # returns the encrypted version of :ssn
  user.redacted_data.has_key?(:email) # false
  user.save

  user = User.load
  user.data { email: 'personal@email.com' }
```

When you set a redacted attribute the data is *immediately* redacted and the attribute replaced.
This is to avoid confusion or inconsistency when passing a record around that might be freshly created or loaded from the DB.

```
  user = User.new user_data: { ssn: '123-45-6789', email: 'personal@email.com' }
  
  user.user_data[:ssn] # nil
```

### Note on Updating Data

Changes within the hash may not be saved

To ensure ActiveRecord saves changed data, you should always update the hash entirely, not keys within the hash.

```
  user = User.new user_data: { ssn: '123-45-6789', email: 'personal@email.com' }
  
  user.user_data[:email] = 'new_address@gmail.com'
  user.save!
  
  user.reload
  user.user_data[:email] # 'personal@email.com'
```

### attr_redacted with database persistence

By default, `attr_redacted` stores the redacted data in `:redacted_<attribute>`.

Create or modify the table that your model uses to add a column with the `redacted_` prefix (which can be modified, see below), e.g. `redacted_ssn` via a migration like the following:

```ruby
  create_table :users do |t|
    t.string :name
    t.jsonb :redacted_user_data
    t.timestamps
  end
```

### Specifying the redacted attribute name

By default, the redacted attribute name is `redacted_#{attribute}` (e.g. `attr_redacted :data` would create an attribute named `redacted_data`). So, if you're storing the redacted attribute in the database, you need to make sure the `redacted_#{attribute}` field exists in your table. You have a couple of options if you want to name your attribute or db column something else, see below for more details.


## attr_redacted options

#### Options are evaluated
All options will be evaluated at the instance level.

### Default options

The following are the default options used by `attr_redacted`:

```ruby
  prefix:            'redacted_',
  suffix:            '',
  marshal:           false,
  marshaler:         Marshal,
  dump_method:       'dump',
  load_method:       'load',
```

Additionally, you can specify default options for all redacted attributes in your class. Instead of having to define your class like this:

```ruby
  class User
    attr_redacted :email, prefix: '', suffix: '_redacted'
    attr_redacted :ssn, prefix: '', suffix: '_redacted'
    attr_redacted :credit_card, prefix: '', suffix: '_redacted'
  end
```

You can simply define some default options like so:

```ruby
  class User
    attr_redacted_options.merge!(prefix: '', :suffix => '_crypted')
    attr_redacted :email
    attr_redacted :ssn
    attr_redacted :credit_card
  end
```

This should help keep your classes clean and DRY.

### The `:attribute` option

You can simply pass the name of the redacted attribute as the `:attribute` option:

```ruby
  class User
    attr_redacted :data, attribute: 'obfuscated_data'
  end
```

This would generate an attribute named `obfuscated_data`


### The `:prefix` and `:suffix` options

If you don't like the `redacted_#{attribute}` naming convention then you can specify your own:

```ruby
  class User
    attr_redacted :data, prefix: 'secret_', suffix: '_hidden'
  end
```

This would generate the following attributes: `secret_data_hidden`.

### The `:encode`, `:encode_iv`, and `:default_encoding` options

You're probably going to be storing your redacted attributes somehow (e.g. filesystem, database, etc). You can pass the `:encode` option to automatically encode/decode when encrypting/hashing/decrypting. The default behavior assumes that you're using a string column type and will base64 encode your cipher text. If you choose to use the binary column type then encoding is not required, but be sure to pass in `false` with the `:encode` option.

```ruby
  class User
    attr_redacted :email, key: 'some secret key', encode: true, encode_iv: true
  end
```

The default encoding is `m` (base64). You can change this by setting `encode: 'some encoding'`. See [`Arrary#pack`](http://ruby-doc.org/core-2.3.0/Array.html#method-i-pack) for more encoding options.

## ORMs

### ActiveRecord

If you're using this gem with `ActiveRecord`, you get a few extra features:

## Things to consider before using attr_redacted

#### Data gone immediately
Obviously, anything you decide to digest or remove, that will be done immediately and you will have no way to recover that data (except keeping a copy of the original hash)

#### Searching, joining, etc
You cannot search encrypted or hashed data (or, obviously, removed data), and because you can't search it, you can't index it either. You also can't use joins on the redacted data. Data that is securely encrypted is effectively noise. 
So any operations that rely on the data not being noise will not work. If you need to do any of the aforementioned operations, please consider using database and file system encryption along with transport encryption as it moves through your stack.
Since redacting uses a hash that is comparable, you could still index digested columns

#### Data leaks
Please also consider where your data leaks. If you're using attr_redacted with Rails, it's highly likely that this data will enter your app as a request parameter. You'll want to be sure that you're filtering your request params from you logs or else your data is sitting in the clear in your logs. [Parameter Filtering in Rails](http://apidock.com/rails/ActionDispatch/Http/FilterParameters) Please also consider other possible leak points.

#### Metadata regarding your crypto implementation
It is advisable to also store metadata regarding the circumstances of your encrypted data. Namely, you should store information about the key used to encrypt your data, as well as the algorithm. Having this metadata with every record will make key rotation and migrating to a new algorithm signficantly easier. It will allow you to continue to decrypt old data using the information provided in the metadata and new data can be encrypted using your new key and algorithm of choice.

## Testing
To verify you've configured redaction properly in your tests, use `attr_redacted?` and `attr_redact_hash`

Given class:

```ruby
  class User
    attr_redacted :data, redact: { :ssn => :remove, :email => :encrypt }
  end
```

### Minitest
```ruby
  def test_should_redact_dataa
    expected_hash = { :ssn => :remove, :email => :encrypt }
    assert User.new.attr_redacted?(:data)
    assert_equal expected_hash, User.new.data_redact_hash
  end
```

### RSpec
```ruby
  it "should redact data"
    expect(User.new.attr_redacted?(:data)).to be_truthy
    expect(User.new.data_redact_hash).to eq({ :ssn => :remove, :email => :encrypt })
  end
```



## Note on Patches/Pull Requests

* Fork the project.
* Make your feature addition or bug fix.
* Add tests for it. This is important so I don't break it in a
  future version unintentionally.
* Commit, do not mess with rakefile, version, changelog, or history.
* Send me a pull request. Bonus points for topic branches.
