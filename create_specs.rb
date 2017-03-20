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

  def set_class_name
    begin
      File.read('manifests/init.pp').each_line do |l|
        if l.match(/^class/)
          return l.match(/class (.*) /).captures[0]
        end
      end
    rescue
      puts 'Did not get a class name from manifests/init.pp, using the current working dir.'
      return Dir.pwd
    end
  end

  def set_params
    my_class = @catalog['data']['resources'].select do |r|
      r['type'] == 'Class' and r['title'] == @class_name.capitalize
    end
    @params = my_class[0]['parameters']
  end

  def clean_out_catalog
    @catalog['data']['resources'].delete_if do |h|
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
    @content += "  let(:params) do\n    " +
    @params.awesome_inspect(
      :index  => false,
      :indent => -2,
      :plain  => true,
    ).gsub(/\n/m, "\n    ") +
    "\n  end\n\n"
  end

  def generate_examples_section
    @catalog['data']['resources'].each do |r|
      @content +=
"  it {
    is_expected.to contain_#{r['type'].downcase}('#{r['title']}').with({
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
        (r['parameters']['ensure'] == 'file' or r['parameters']['ensure'] == 'present')

        if r['parameters'].has_key?('content')
          r['parameters']['content'].gsub!('\\') { '\\\\' }
          r['parameters']['content'].gsub!(/"/, '\"')
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
