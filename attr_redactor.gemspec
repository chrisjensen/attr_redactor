# -*- encoding: utf-8 -*-

lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'attr_redactor/version'
require 'date'

Gem::Specification.new do |s|
  s.name    = 'attr_redactor'
  s.version = AttrRedactor::Version.string
  s.date    = Date.today

  s.summary     = 'Redact JSON attributes before saving'
  s.description = 'Generates attr_accessors that redact certain values in the JSON structure before saving.'

  s.authors   = ['Chris Jensen']
  s.email    = ['chris@broadthought.co']
  s.homepage = 'http://github.com/chrisjensen/attr_redactor'

  s.has_rdoc = false
  s.rdoc_options = ['--line-numbers', '--inline-source', '--main', 'README.rdoc']

  s.require_paths = ['lib']

  s.files      = `git ls-files`.split("\n")
  s.test_files = `git ls-files -- test/*`.split("\n")

  s.required_ruby_version = '>= 2.0.0'

  s.add_dependency('hash_redactor', ['~> 0.3.1'])
  # support for testing with specific active record version
  activerecord_version = if ENV.key?('ACTIVERECORD')
    "~> #{ENV['ACTIVERECORD']}"
  else
    '~> 3.0'
  end
  s.add_development_dependency('activerecord', activerecord_version)
  s.add_development_dependency('actionpack', activerecord_version)
  s.add_development_dependency('datamapper')
  s.add_development_dependency('rake')
  s.add_development_dependency('minitest')
  s.add_development_dependency('sequel')
  if defined?(RUBY_ENGINE) && RUBY_ENGINE.to_sym == :jruby
    s.add_development_dependency('activerecord-jdbcsqlite3-adapter')
    s.add_development_dependency('jdbc-sqlite3', '< 3.8.7') # 3.8.7 is nice and broke
  else
    s.add_development_dependency('sqlite3')
  end
  s.add_development_dependency('dm-sqlite-adapter')
  s.add_development_dependency("codeclimate-test-reporter")
end
