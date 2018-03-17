#!/usr/bin/ruby

require 'json'
require 'yaml'
require 'fileutils'
require 'awesome_print'
require 'optparse'

$default_output = 'spec/classes/init_spec.rb'

# FIXME. It would be cleaner if this was turned into a default options, with an
# option to specify a custom options file on the command line.
#
def default_excludes
  config = [File.dirname($0), 'config.yml'].join('/')
  return [] unless File.exists?(config)
  return YAML.load_file(config)['default_excludes']
end

def parse_arguments
  options = Hash.new { |h, k| h[k] = [] }
  options[:excludes] = default_excludes
  options[:only_include] = []

  catalog_file = String.new
  output_file = $default_output

  OptionParser.new do |opts|
    opts.banner = "Usage: #{File.basename($0)} [options]"
    opts.on('-c', '--catalog CATALOG', 'Path to the catalog JSON file') do |c|
      catalog_file = c
    end
    opts.on('-o', '--output OUTPUTFILE', 'Path to the output Rspec file') do |o|
      output_file = o
    end
    opts.on('-x', '--exclude RESOURCE', [
      'Resources to exclude. String or Regexp. ',
      'Repeat this option to exclude multiple resources'].join) do |r|
      options[:excludes] << r
    end
    opts.on('-i', '--include RESOURCE',
      'Resources to include despite the exclude list.') do |r|
      options[:excludes].delete_if { |x| x == r }
    end
    opts.on('-I', '--only-include RESOURCE',
      'Only include these resources and exclude everything else') do |r|
      options[:only_include] << r
    end
    opts.on('-h', '--help', 'Print this help') do
      puts opts
      exit 0
    end
  end.parse!

  if catalog_file.empty?
    puts 'You must specify a catalog file via -c'
    exit 1
  end

  if ! File.exists?(catalog_file)
    puts "#{catalog_file}: not found"
    exit 1
  end

  return [catalog_file, output_file, options]
end

# Class for rewriting a catalog as a spec file.
#
class SpecWriter
  def initialize(catalog_file, output_file, options)
    @catalog_file = catalog_file
    @output_file = output_file
    @options = options

    @catalog = JSON.parse(File.read(@catalog_file))
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
  # The assumption here is that the class name was used to compile the input
  # catalog is found immediately after Class[main] in the resources array. This
  # is true of all catalogs I have seen so far.
  #
  def class_name
    @catalog['resources'].each_with_index do |r,i|
      if r['type'] == 'Class' and r['title'] == 'main'
        return @catalog['resources'][i+1]['title'].downcase
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
    if ! @options[:only_include].empty?
      @catalog['resources'].delete_if do |resource|
        delete_me = true
        @options[:only_include].each do |i|
          type, title = i.tr('[]',' ').split(' ')
          resource['type'] == type and resource['title'] == title and delete_me = false
        end
        delete_me
      end
    else
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
  end

  # Generate the actual file content, using the @content instance variable.
  #
  def generate_content
    generate_head_section
    generate_params_section
    generate_examples_section
    generate_tail_section
  end

  def generate_head_section
    @content =
      "require 'spec_helper'\n" +
      "require 'json'\n\n"      +
      "describe '#{@class_name}' do\n"
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

  def generate_examples_section
    @catalog['resources'].each do |r|
      title = r['title'].gsub(/'/, "\\\\'")
      @content +=
        "  it 'is expected to contain #{r['type'].downcase} #{title}' do\n" +
        "    is_expected.to contain_#{r['type'].downcase}('#{title}').with({\n"

      r['parameters'].each do |k, v|
        unless r['type'] == 'File' and k == 'content'
          if v.is_a?(String)
            v.gsub!(/'/, "\\\\'")
            @content += "      '#{k}' => '#{v}',\n"
          elsif [Fixnum, TrueClass, FalseClass].include?(v.class)
            @content += "      '#{k}' => '#{v}',\n"
          elsif v.is_a?(Array)
            @content += "      '#{k}' => #{v},\n"
          end
        end
      end

      @content += "    })\n  end\n\n"

      if r['type'] == 'File' and
        (r['parameters']['ensure'] == 'file' or
         r['parameters']['ensure'] == 'present' or
         ! r['parameters'].has_key?('ensure'))

        if r['parameters'].has_key?('content')
          begin
            r['parameters']['content'].gsub!('\\') { '\\\\' }
            r['parameters']['content'].gsub!(/"/, '\"')
            r['parameters']['content'].gsub!(/\@/, '\@')
            r['parameters']['content'].gsub!(/\$;/, '\\$;')
            r['parameters']['content'].gsub!(
              /\$EscapeControlCharactersOnReceive/,
              '\\$EscapeControlCharactersOnReceive')  # A weird special Ruby
          rescue
          end
        end

        unless r['parameters']['content'].nil?
          @content +=
            "  it 'is expected to contain expected content for file "   +
                          "#{r['title']}' do\n"                         +
            "    [\n\n"                                                 +
            "\"#{r['parameters']['content']}\",\n\n"                    +
            "    ].map{|text| text.split(\"\\n\")}.each do |line|\n\n"  +
            "      verify_contents(catalogue, '#{r['title']}', line)\n" +
            "    end\n"                                                 +
            "  end\n\n"
        end
      end
    end
  end

  def generate_tail_section
    file_name = @class_name.gsub(/::/, '__')
    unless ! @options[:only_include].empty?
      @content +=
        "  it 'should write a compiled catalog' do\n" +
        "    is_expected.to compile.with_all_deps\n"  +
        "    File.write(\n"                           +
        "      'catalogs/#{file_name}.json',\n"       +
        "      PSON.pretty_generate(catalogue)\n"     +
        "    )\n"                                     +
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
  catalog_file, output_file, options = parse_arguments
  SpecWriter.new(catalog_file, output_file, options).write
end
