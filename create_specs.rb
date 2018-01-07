#!/usr/bin/ruby

require 'json'
require 'fileutils'
require 'awesome_print'

class CreateSpecs
  def initialize
    if ARGV.empty?
      usage
    end

    @catalog = JSON.parse(File.read(ARGV[0]))
    convert_to_v4_catalog

    @class_name = set_class_name
    @params = set_params

    @content = String.new

    clean_out_catalog
    generate_content
    write_content_to_file
  end

  def usage
    puts "Usage: #{$0} <catalog_file>"
    exit 1
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
      h['type'] == 'Stage'  or h['type'] == 'Class' or
      h['type'] == 'Anchor' or h['type'] == 'Notify' or
      h['type'] == 'Node'   or h['type'] =~ /::/
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
