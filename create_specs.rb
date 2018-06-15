#!/usr/bin/env ruby

require 'json'
require 'yaml'
require 'fileutils'
require 'awesome_print'
require 'optparse'
require 'digest'

# Support Ruby < 2.4.0. In Ruby 2.4.0, the Fixnum and Bignum types were unified
# as Integer.
#
if not defined?(Fixnum)
  class Fixnum < Integer
  end
end

$default_config = [File.dirname($0), 'config.yml'].join('/')

def parse_arguments
  options = YAML.load_file($default_config)

  OptionParser.new do |opts|
    opts.banner = "Usage: #{File.basename($0)} [options]"
    opts.on('-f', '--config_file CONFIG', 'Path to config file') do |opt|
      options = YAML.load_file(opt)
    end
    opts.on('-c', '--catalog CATALOG', 'Path to the catalog JSON file') do |opt|
      options[:catalog_file] = opt
    end
    opts.on('-C', '--class CLASS', 'Class (or node) name under test') do |opt|
      options[:class_name] = opt
    end
    opts.on('-o', '--output OUTPUTFILE', 'Path to the output Rspec file') do |opt|
      options[:output_file] = opt
    end
    opts.on('-x', '--exclude RESOURCE', [
      'Resources to exclude. String or Regexp. ',
      'Repeat this option to exclude multiple resources'].join) do |opt|
      options[:excludes] << opt
    end
    opts.on('-i', '--include RESOURCE',
      'Resources to include despite the exclude list.') do |opt|
      options[:excludes].delete_if { |x| x == opt }
    end
    opts.on('-I', '--only-include RESOURCE',
      'Only include these resources and exclude everything else. Regexp supported') do |opt|
      options[:only_include] << opt
    end
    opts.on('-m', '--md5sums',
      'Use md5sums instead of full file content to validate file content') do |opt|
      options[:md5sums] = opt
    end
    opts.on('-t', '--[no-]compile-test', 'Include or exclude the catalog compilation test') do |opt|
      options[:compile_test] = opt
    end
    opts.on('-h', '--help', 'Print this help') do
      puts opts
      exit 0
    end
  end.parse!

  catalog_file = options[:catalog_file]

  if catalog_file.empty?
    puts 'You must specify a catalog file via -c'
    exit 1
  end

  if ! File.exists?(catalog_file)
    puts "#{catalog_file}: not found"
    exit 1
  end

  return options
end

# Class for rewriting a catalog as a spec file.
#
class SpecWriter
  def initialize(options)
    @options = options
    @output_file = options[:output_file]

    @catalog = JSON.parse(File.read(options[:catalog_file]))
    convert_to_v4

    @content = String.new
    @class_name = class_name
    @params = params
  end

  def write
    clean_catalog
    generate_content
    write_to_file
  end

  private

  # Set the class name based on the catalog content.
  #
  # The assumption here is that the class name that was used to compile the
  # input catalog is the first resource of type Class found after the
  # Class[main] in the resources array. This is true of all catalogs I have
  # seen so far.
  #
  def class_name
    return @options[:class_name] if not @options[:class_name].nil?
    class_main_found = false
    @catalog['resources'].each_with_index do |r,i|
      if r['type'] == 'Class' and r['title'] == 'main'
        class_main_found = true
        next
      end
      if class_main_found and r['type'] == 'Class'
        return r['title'].downcase
      end
    end
  end

  def capitalize(string)
    string.split(/::/).map{|x| x.capitalize}.join('::')
  end

  def params
    begin
      resources = @catalog['resources'].select do |r|
        r['type'] == 'Class' and r['title'] == capitalize(@class_name)
      end
      return resources[0]['parameters']
    rescue
    end
    return nil
  end

  # Convert a v3 catalog to v4 format. We are of course not really
  # "converting" in that Puppet (I assume) could not actually use it. For our
  # purposes, however, we care only about the contents of the resources array.
  #
  # If we find a key at @catalog['data'], then we move
  # @catalog['data']['resources'] to @catalog['resources'].
  #
  def convert_to_v4
    if @catalog.has_key?('data')
      @catalog['resources'] = @catalog['data']['resources']
      @catalog.delete('data')
    end
  end

  # Any default or command-line specified exclusions are removed from the
  # catalog here. Or, if only_include is specified, clean out everything other
  # than what is specified there.
  #
  def clean_catalog
    if @options[:only_include].empty?
      clean_by_includes
    else
      clean_by_only_includes
    end
  end

  def clean_by_only_includes
    @catalog['resources'].delete_if do |resource|

      typ = resource['type']
      tit = resource['title']

      delete_me = true

      # TODO: handle invalid regexps gracefully.
      #
      @options[:only_include].each do |i|
        type, title = i.tr('[]',' ').split(' ') if i =~ /\[/
        if i =~ /^\/.*\/$/         # e.g. /File/
          regexp("arg =~ #{i}", typ) and delete_me = false
        elsif i =~ /.*\[\/.*\/\]/  # e.g. File[/.*/]
          typ == type and regexp("arg =~ #{title}", tit) and delete_me = false
        else
          typ == type and tit == title and delete_me = false
        end
      end
      delete_me
    end
  end

  def regexp(regexp, arg)
    begin
      eval regexp
    rescue SyntaxError
      raise "Regexp in #{regexp} invalid (see your only_includes list)"
    end
  end

  def clean_by_includes
    delete_me = true
    @catalog['resources'].delete_if do |resource|
      delete_me = false
      @options[:excludes].each do |x|
        delete_me = true if resource['type'] == x
        delete_me = true if
          x =~ /^\/.*\/$/ and eval "resource['type'] =~ #{x}"
      end
      delete_me
    end
  end

  # Generate the actual file content, using the @content instance variable.
  #
  def generate_content
    generate_head_section
    generate_setup_section
    generate_params_section
    generate_examples_section
    generate_tail_section
  end

  def generate_head_section
    @content = "require 'spec_helper'\n"
    @content += "require 'json'\n"   if not @params.nil?
    @content += "require 'digest'\n" if @options[:md5sums]
    @content += "\ndescribe '#{@class_name}' do\n"
  end

  def generate_setup_section
    return if @options[:setup].empty?
    setup = @options[:setup]
    if setup.has_key?(:pre_condition)
      @content +=
        "  let(:pre_condition) do\n" +
        '    """'"\n"
      setup[:pre_condition].each do |l|
        @content += "    #{l}\n"
      end
        @content +=
          '    """'"\n" +
          "  end\n\n"
    end
    if setup.has_key?(:hiera_config)
      @content += "  let(:hiera_config){ '#{setup[:hiera_config]}' }\n\n"
    end
    if setup.has_key?(:facts)
      @content +=
        "  let(:facts) do\n    " +
        setup[:facts].awesome_inspect(
          :index  => false,
          :indent => -2,
          :plain  => true,
        )
        .
        gsub(/\n/m, "\n    ") + "\n  end\n\n"
    end
  end

  def generate_params_section
    unless @params.nil?
      @content += "  let(:params) do\n    " +
        @params.awesome_inspect(
          :index  => false,
          :indent => -2,
          :plain  => true,
        )
        .
        gsub(/\n/m, "\n    ") + "\n  end\n\n"
    end
  end

  def matcher(type)
    "contain_#{type.downcase.gsub '::', '__'}"
  end

  def generate_examples_section
    @catalog['resources'].each do |r|

      type       = r['type']
      title      = r['title'].gsub /'/, "\\\\'"
      parameters = r['parameters']

      if parameters.nil?
        @content +=
          "  it 'is expected to contain #{type.downcase} #{title}' do\n" +
          "    is_expected.to #{matcher(type)}('#{title}')\n"            +
          "  end\n\n"
        next
      end

      @content +=
        "  it 'is expected to contain #{type.downcase} #{title}' do\n" +
        "    is_expected.to #{matcher(type)}('#{title}').with({\n"

      parameters.each do |k, v|
        unless type == 'File' and k == 'content'
          if v.class == String
            v.gsub! /'/, "\\\\'"
            @content += "      '#{k}' => '#{v}',\n"
          elsif [Integer, TrueClass, FalseClass].include?(v.class)
            @content += "      '#{k}' => '#{v}',\n"
          elsif [Array, Hash].include?(v.class)
            @content += "      '#{k}' => #{v},\n"
          else
            raise "Unhandled input at #{type}[#{title}] of class #{v.class}"
          end
        end
      end

      @content += "    })\n  end\n\n"

      ensr = parameters['ensure']
      cont = parameters['content']

      if type == 'File' and
        not cont.nil? and
        (ensr == 'file' or ensr == 'present' or
         not parameters.has_key?('ensure'))

        mod = cont.clone

        if parameters.has_key?('content')
          begin
            mod.gsub!('\\') { '\\\\' }
            mod.gsub! /"/, '\"'
            mod.gsub! /\@/, '\@'
            mod.gsub! /\$;/, '\\$;'
            mod.gsub!(
              /\$EscapeControlCharactersOnReceive/,
              '\\$EscapeControlCharactersOnReceive') # A weird special Ruby
          rescue
          end
        end

        if not cont.nil?
          if @options[:md5sums]
            generate_md5sum_check(title, cont)
          else
            generate_content_check(title, mod)
          end
        end
      end
    end
  end

  def generate_md5sum_check(title, content)
    md5 = Digest::MD5.hexdigest(content)
    @content +=
      "  it 'is expected to contain expected content for file "  +
                    "#{title}' do\n"                             +
      "    content = catalogue.resource('file', '#{title}').send(:parameters)[:content]\n" +
      "    md5 = Digest::MD5.hexdigest(content)\n"               +
      "    expect(md5).to eq '#{md5}'\n"                         +
      "  end\n\n"
  end

  def generate_content_check(title, content)
    @content +=
      "  it 'is expected to contain expected content for file "   +
                    "#{title}' do\n"                              +
      "    [\n\n"                                                 +
      "\"#{content}\",\n\n"                                       +
      "    ].map{|text| text.split(\"\\n\")}.each do |line|\n\n"  +
      "      verify_contents(catalogue, '#{title}', line)\n"      +
      "    end\n"                                                 +
      "  end\n\n"
  end

  def generate_tail_section
    file_name = @class_name.gsub /::/, '__'
    unless not @options[:compile_test]
      @content +=
        "  it 'should write a compiled catalog' do\n"  +
        "    is_expected.to compile.with_all_deps\n"   +
        "    File.write(\n"                            +
        "      'catalogs/#{file_name}.json',\n"        +
        "      PSON.pretty_generate(catalogue)\n"      +
        "    )\n"                                      +
        "  end\n"
    end
    @content += "end\n"
  end

  def write_to_file
    puts("Writing out as #{@output_file}")
    FileUtils.mkdir_p 'spec/classes'
    File.open(@output_file, 'w') {|f| f.write(@content)}
  end
end

# Main.
if $0 == __FILE__
  options = parse_arguments
  SpecWriter.new(options).write
end
