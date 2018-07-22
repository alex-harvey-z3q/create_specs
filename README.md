# create_specs.rb

Release 3.0.0-pre

## Status

This project is currently being rewritten in Crystal.

## Overview

This script can be used to generate Rspec-puppet examples for all of the resources in a Puppet JSON catalog document. The intended use-cases include quickly generating default Rspec tests in a project that doesn't have any; and it can also be useful when refactoring Puppet modules.

It is assumed that the user already knows how to set up Rspec-puppet for a Puppet module (i.e. how to create the `.fixtures.yml`, `Gemfile`, `spec/spec_helper.rb` etc).  If not, consider reading my [blog post](http://razorconsulting.com.au/setting-up-puppet-module-testing-from-scratch-part-ii-beaker-for-module-testing.html).

## Dependencies

To install dependencies:

~~~ text
shards install
~~~

## Installation

TODO.

## Usage

To run via crystal run:

~~~ text
$ crystal run create_specs.rb -- [options]
~~~

e.g.

~~~ text
$ crystal run create_specs.rb -- -c spec/fixtures/ntp.json
~~~

Help message:

```
$ create_specs.rb -h
Usage: create_specs.rb [options]
  -f, --config_file CONFIG    Path to config file
  -c, --catalog CATALOG       Path to the catalog JSON file
  -C, --class CLASS           Class (or node) name under test
  -o, --output OUTPUTFILE     Path to the output Rspec file
  -x, --exclude RESOURCE      Resources to exclude. String or Regexp. Repeat this option to exclude multiple resources
  -i, --include RESOURCE      Resources to include despite the exclude list.
  -I, --only-include RESOURCE Only include these resources and exclude everything else. Regexp supported
  -m, --md5sums               Use md5sums instead of full file content to validate file content
  -t, --[no-]compile-test     Include or exclude the catalog compilation test
  -h, --help                  Print this help
```

### Basic usage

Basic usage:

```
$ cd /path/to/puppet/module
$ create_specs.rb -c /path/to/catalog.json
```

This will cause the resources in `catalog.json` to be rewritten as Rspec-puppet examples in `spec/classes/init_spec.rb`, which is the default output file.

By default, the script excludes all defined types as well as Class, Anchor, Notify and Node resources (see `config.yml`).

### include option

If you want to override and include one or more of these, use the `-i` option:

```
$ create_specs.rb -c catalog.json -i Class -i Node
```

To include defined types:

```
$ create_specs.rb -c catalog.json -i /::/
```

Due to a quirk of the implementation (again, see `config.yml`) it is not possible to include a specific defined type only. Using `-i My::Type` would not override the default behaviour to exclude everything matching `/::/`. To work around that use -I.

### exclude option

If you want to exclude additional resource types, use the `-x` option:

```
$ create_specs.rb -c catalog.json -x User -x Group
```

### only include option

It is also possible to exclude everything other than a list of resources you care about. Use the `-I` option for this:

```
$ create_specs.rb -c catalog.json -I 'Service[ntp]' -I 'File[ntp]'
```

This option can also accept regular expressions, e.g.:

Only include all files:

```
$ create_specs.rb -c catalog.json -I '/File/'  # or
$ create_specs.rb -c catalog.json -I 'File[/.*/]'
```

Only include files in /etc/ssl:

```
$ create_spec.rb -c catalog.json -I 'File[/\/etc\/ssl/]'
```

### output option

To specify a different output file:

```
$ create_specs.rb -c /path/to/catalog.json -o path/to/output_spec.rb
```

### class name option

By default, the class name that was used to generate the catalog is guessed. In some edge-cases (e.g. if a pre-condition is used in the set up that first declares a different class) the auto-detected class is wrong. To get around this, use the -C option:

```
$ create_specs.rb -c /path/to/catalog.json -C class
```

### compile test option

The default behaviour is to include a compile test as follows:

``` ruby
  it 'should write a compiled catalog' do
    is_expected.to compile.with_all_deps
    File.write(
      'catalogs/class_name.json',
      PSON.pretty_generate(catalogue)
    )
  end
```

This can be disabled by specifying `--no-compile-test`.

### Specifying custom setup

By using the -f option, it is possible to pass a custom config.yml file with a custom setup section in it. For example, if your config.yml contained:

``` yaml
:setup:
  :pre_condition:
    - hiera_include('classes')
  :hiera_config: spec/fixtures/hiera.yaml
  :facts:
    foo: bar
    baz: qux
```

This would result in auto-generated Rspec code with:

``` ruby
  let(:pre_condition) do
    """
    hiera_include('classes')
    """
  end

  let(:hiera_config){ 'spec/fixtures/hiera.yaml' }

  let(:facts) do
    {
      "foo" => "bar",
      "baz" => "qux"
    }
  end
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

