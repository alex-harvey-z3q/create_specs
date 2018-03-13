# create_specs.rb

Release 2.2.0

## Overview

This script can be used to generate Rspec-puppet examples for all of the resources in a Puppet JSON catalog document. The intended use-cases include quickly generating default Rspec tests in a project that doesn't have any; and it is also be useful when refactoring Puppet modules.

It is assumed that the user already knows how to set up Rspec-puppet for a Puppet module (i.e. how to create the `.fixtures.yml`, `Gemfile`, `spec/spec_helper.rb` etc).  If not, consider reading my [blog post](http://razorconsulting.com.au/setting-up-puppet-module-testing-from-scratch-part-ii-beaker-for-module-testing.html).

## Dependencies

This tool uses the [awesome_print](https://github.com/awesome-print/awesome_print) Gem.

Also, be aware that the generated spec depends on the `verify_contents` method that is normally found inside Puppetlabs-spec-helper.

## Usage

Help message:

```
$ create_specs.rb -h
Usage: create_specs.rb [options]
    -c, --catalog CATALOG            Path to the catalog JSON file
    -o, --output OUTPUTFILE          Path to the output Rspec file
    -x, --exclude RESOURCE           Resources to exclude. String or Regexp. Repeat this option to exclude multiple resources
    -i, --include RESOURCE           Resources to include overriding default exclude list.
    -h, --help                       Print this help
```

Basic usage:

```
$ cd /path/to/puppet/module
$ create_specs.rb -c /path/to/catalog.json
```

This will cause the resources in `catalog.json` to be rewritten as Rspec-puppet examples in `spec/classes/init_spec.rb`, which is the default output file.

By default, the script excludes all defined types as well as Class, Anchor, Notify and Node resources (see `config.yml`).

If you want to override and include one or more of these, use the `-i` option:

```
$ create_specs.rb -c catalog.json -i Class -i Node
```

If you want to exclude additional resource types, use the `-x` option:

```
$ create_specs.rb -c catalog.json -x User -x Group
```

To include defined types:

```
$ create_specs.rb -c catalog.json -i /::/
```

Due to a quirk of the implementation (again, see `config.yml`) it is not possible to include a specific defined type only. Using `-i My::Type` would not override the default behaviour to exclude everything matching `/::/`.

To specify a different output file:

```
$ create_specs.rb -c /path/to/catalog.json -o path/to/output_spec.rb
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

