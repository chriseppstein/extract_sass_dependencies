#!/usr/bin/env ruby

require 'sass'
require 'sass/plugin/staleness_checker'
require 'compass'
require 'pathname'

class DependencyExtractor
  class Asset < Struct.new(:filename, :importer, :children)
    def initialize(*args)
      super
      self.children ||= []
    end

    def dependencies
      children.map {|child| [child, child.dependencies] }.flatten
    end
  end

  include Sass::Plugin

  def initialize(options = {})
    @options = Sass::Engine.normalize_options(options)
  end

  def analyze(*files)
    files.map {|f| analyze_file(f) }
  end

  def analyze_file(f, importer = importer)
    children = checker.send(:dependencies, f, importer).map{|c| analyze_file(*c) }
    Asset.new(f, importer, children)
  end

  def importer
    @importer ||= @options[:filesystem_importer].new(".")
  end

  def checker
    @checker ||= StalenessChecker.new(@options)
  end
end

if __FILE__ == $0
  require 'optparse'
  # XXX Need to configure compass correctly here.
  $options = {:format => :flat}
  parser = OptionParser.new do |opt|
    opt.banner = "USAGE: extract-sass-dependencies [options] sass_file [sass_file...]"
    opt.on("-f [FORMAT]", "--format [FORMAT]", [:flat, :nested, :nested_html], "Output format: flat, nested, or nested_html") do |format|
      $options[:format] = format
    end
    opt.on("--full-paths", "Output full paths instead of cleaned output for human readability.") do 
      $options[:full_paths] = true
    end
    opt.on( "--trace", "Show a stacktrace on error.") do
      $options[:trace] = true
    end
  end
  parser.parse!($*)
  if $*.size == 0
    $stderr.puts parser.to_s
    exit(1)
  end
  extractor = DependencyExtractor.new(Compass.configuration.to_sass_engine_options)

  def clean_filename(f)
    if $options[:full_paths]
      File.expand_path(f)
    else
      Compass::Frameworks::ALL.each do |framework|
        if f.start_with?(framework.stylesheets_directory)
          return "(#{framework.name})#{f[framework.stylesheets_directory.size..-1]}"
        end
      end
      Pathname.new(File.expand_path(f)).relative_path_from(Pathname.new(File.expand_path("."))).to_s
    end
  end
  def flat_output(assets)
    puts(assets.map do |asset|
      asset.dependencies.map{|d| clean_filename(d.filename)}
    end.flatten.uniq.join("\n"))
  end
  def nested_output(assets, depth = 0)
    assets.each do |asset|
      puts(("  " * depth) + clean_filename(asset.filename))
      nested_output(asset.children, depth + 1)
    end
  end
  def nested_html_output(assets, depth = 0)
    puts "#{'  ' * depth}<ol>"
    assets.each do |asset|
      if asset.children.any?
        puts(("  " * (depth+1)) + "<li>" + clean_filename(asset.filename))
        nested_html_output(asset.children, depth + 2)
        puts(("  " * (depth+1)) + "</li>")
      else
        puts(("  " * (depth+1)) + "<li>" + clean_filename(asset.filename) + "</li>")
      end
    end
    puts "#{'  ' * depth}</ol>"
  end
  begin
    send(:"#{$options[:format]}_output", extractor.analyze(*$*))
  rescue => e
    $stderr.puts "#{e.class.name}: #{e.message}"
    $stderr.puts e.backtrace.join("\n")
  end
end
