#!/usr/bin/ruby

require 'json'
require 'yaml'
require 'fileutils'
require 'awesome_print'
require 'optparse'

class CreateSpecs
  def initialize
    @catalog_file, @options = parse_arguments

    @catalog = JSON.parse(File.read(@catalog_file))
    convert_to_v4_catalog

    @content = String.new

    @class_name = set_class_name
    @params = set_params

    clean_out_catalog
    generate_content
    write_content_to_file
  end

  def parse_arguments
    catalog_file = String.new
    options = Hash.new { |h, k| h[k] = [] }
    options[:excludes] = default_excludes
    OptionParser.new do |opts|
      opts.banner = "Usage: #{File.basename($0)} [options]"
      opts.on('-c', '--catalog CATALOG', 'Path to the catalog JSON file') do |c|
        catalog_file = c
      end
      opts.on('-x', '--exclude RESOURCE',
 'Resources to exclude. String or Regexp. Repeat this option to exclude multiple resources') do |r|
        options[:excludes] << r
      end
      opts.on('-i', '--include RESOURCE',
 'Resources to include overriding default exclude list.') do |r|
        options[:excludes].delete_if { |x| x == r }
      end
      opts.on('-h', '--help', 'Print this help') do
        puts opts
        exit 0
      end
    end.parse!

    unless catalog_file
      raise OptionParser::MissingArgument, 'You must specify a catalog file via -c'
    end

    unless File.exists?(catalog_file)
      puts "#{catalog_file}: not found"
      exit 1
    end

    return [catalog_file, options]
  end

  def default_excludes
    config = [File.dirname($0), 'config.yml'].join('/')
    return [] unless File.exists?(config)
    return YAML.load_file(config)['default_excludes']
  end

  def convert_to_v4_catalog
    if @catalog.has_key?('data')
      @catalog['resources'] = @catalog['data']['resources']
      @catalog.delete('data')
    end
  end

  def set_class_name
    @catalog['resources'].each_with_index do |r,i|
      if r['type'] == 'Class' and r['title'] == 'main'
        return @catalog['resources'][i+1]['title'].downcase
      end
    end
  end

  def capitalize(string)
    string.split(/::/).map{|x| x.capitalize}.join('::')
  end

  def set_params
    begin
      return @catalog['resources'].select{|r| r['type']=='Class' and r['title']==capitalize(@class_name)}[0]['parameters']
    rescue
      return nil
    end
  end

  def clean_out_catalog
    @catalog['resources'].delete_if do |h|
      ret = false
      @options[:excludes].each do |x|
        ret = true if h['type'] == x
        ret = true if x =~ /^\/.*\/$/ and eval "h['type'] =~ #{x}"
      end
      ret
    end
  end

  def generate_content
    generate_head_section
    generate_params_section
    generate_examples_section
    generate_tail_section
  end

  def generate_head_section
    @content = "require 'spec_helper'\nrequire 'json'\n\ndescribe '#{@class_name}' do\n"
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
      @content += <<-EOF
  it 'is expected to contain #{r['type'].downcase} #{title}' do
    is_expected.to contain_#{r['type'].downcase}('#{title}').with({
      EOF

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
        (r['parameters']['ensure'] == 'file' or r['parameters']['ensure'] == 'present' or ! r['parameters'].has_key?('ensure'))

        if r['parameters'].has_key?('content')
          begin
            r['parameters']['content'].gsub!('\\') { '\\\\' }
            r['parameters']['content'].gsub!(/"/, '\"')
            r['parameters']['content'].gsub!(/\@/, '\@')
            r['parameters']['content'].gsub!(/\$;/, '\\$;')
            r['parameters']['content'].gsub!(/\$EscapeControlCharactersOnReceive/, '\\$EscapeControlCharactersOnReceive')  # A weird special Ruby var I ran into.
          rescue
          end
        end

        unless r['parameters']['content'].nil?
          @content += <<-EOF
  it 'is expected to contain expected content for file #{r['title']}' do
    [

\"#{r['parameters']['content']}\",

    ].map{|text| text.split(\"\\n\")}.each do |line|

      verify_contents(catalogue, '#{r['title']}', line)
    end
  end

          EOF
        end
      end
    end
  end

  def generate_tail_section
    file_name = @class_name.gsub(/::/, '__')
    @content += <<-EOF
  it 'should write a compiled catalog' do
    is_expected.to compile.with_all_deps
    File.write(
      'catalogs/#{file_name}.json',
      PSON.pretty_generate(catalogue)
    )
  end
end
    EOF
  end

  def write_content_to_file
    FileUtils.mkdir_p 'spec/classes'
    File.open('spec/classes/init_spec.rb', 'w') {|f| f.write(@content)}
  end
end

CreateSpecs.new
