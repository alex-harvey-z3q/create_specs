# create_specs.rb

Release 1.3.0

## Overview

This script can be used to generate Rspec-puppet examples for all of the resources in a Puppet JSON catalog document. The intended use-cases include quickly generating default Rspec tests in a project that doesn't have any; and it is also be useful when refactoring Puppet modules.

It is assumed that the user already knows how to set up Rspec-puppet for a Puppet module (i.e. how to create the `.fixtures.yml`, `Gemfile`, `spec/spec_helper.rb` etc).  If not, consider reading my [blog post](http://razorconsulting.com.au/setting-up-puppet-module-testing-from-scratch-part-ii-beaker-for-module-testing.html).

## Dependencies

This tool uses the [awesome_print](https://github.com/awesome-print/awesome_print) Gem.

Also, be aware that the generated spec depends on the `verify_contents` method that is normally found inside Puppetlabs-spec-helper.

## Usage

The script should be run from the root directory of the Puppet module and it takes the path to the catalog file as its only argument:

```
$ cd /path/to/puppet/module
$ create_specs.rb /path/to/catalog.json
```

## Creating the catalog document

While there are a variety of ways of creating a compiled Puppet catalog, the easiest way is to use Rspec-puppet.  Just create a spec file with the following content:

```ruby
require 'spec_helper'

describe 'myclass' do
  let(:params) do
    {
      'param1' => 'value1',
      'param2' => 'value2',
    }
  end

  it {
    File.write(
      'mycatalog.json',
      PSON.pretty_generate(catalogue)
    )
  }
end
```

Then run the tests and you'll have a compiled catalog.

For more detail, see my [other blog post](http://razorconsulting.com.au/dumping-the-catalog-in-rspec-puppet.html).

