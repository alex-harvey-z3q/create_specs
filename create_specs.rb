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
      h['type'] =~ /::/
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
      @content +=
"  it {
    is_expected.to contain_#{r['type'].downcase}('#{title}').with({
"
      r['parameters'].each do |k, v|
        unless r['type'] == 'File' and k == 'content'
          if v.is_a?(String)
            v.gsub!(/'/, "\\\\'")
          end
          @content +=

"      '#{k}' => '#{v}',
"

        end
      end

      @content +=
"    })
  }

"
      if r['type'] == 'File' and
        (r['parameters']['ensure'] == 'file' or r['parameters']['ensure'] == 'present' or ! r['parameters'].has_key?('ensure'))

        if r['parameters'].has_key?('content')
          r['parameters']['content'].gsub!('\\') { '\\\\' }
          r['parameters']['content'].gsub!(/"/, '\"')
          r['parameters']['content'].gsub!(/\@/, '\@')
          r['parameters']['content'].gsub!(/\$;/, '\\$;')
          r['parameters']['content'].gsub!(/\$EscapeControlCharactersOnReceive/, '\\$EscapeControlCharactersOnReceive')  # A weird special Ruby var I ran into.
        end

        @content +=
"  [

\"#{r['parameters']['content']}\",

  ].map{|k| k.split(\"\\n\")}.each do |text|

    it {
      verify_contents(catalogue, '#{r['title']}', text)
    }
  end

"
      end
    end
  end

  def generate_tail_section
    @content += 
"  it {
    is_expected.to compile.with_all_deps
    File.write(
      'catalogs/#{@class_name}.json',
      PSON.pretty_generate(catalogue)
    )
  }
end
"
  end

  def write_content_to_file
    FileUtils.mkdir_p 'spec/classes'
    File.open('spec/classes/init_spec.rb', 'w') {|f| f.write(@content)}
  end
end

CreateSpecs.new
