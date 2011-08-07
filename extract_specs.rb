#!/usr/bin/ruby
require 'logger'
require 'find'

OUTDIR = ARGV[1]

class Rspeccer
  attr_accessor :infile, :outfile

  private
  attr :keyword_counter

  public
  def initialize infile, outfile, loglevel = Logger::INFO
    @infile = infile
    @outfile = outfile
    @keyword_counter = 0
    log.level = loglevel
  end

  def speccify
    log.info "Outputting spec skeleton to #{outfile}"
    File.open(outfile, 'w+') do |out|
      output = [%Q{require '#{infile.split(/\.rb$/)[0].split(%r{^lib/}, 2)[1]}'\n\n}]
      @keyword_counter = 0
      log.info "Counter: #{@keyword_counter}"
      File.open(infile).lines.each do |line|
        output +=
          find_keyword(line, 'module') { |found|
            find_keyword(line, 'class', found) { |found|
              find_keyword(line, 'def', found) { |found|
                #add_endings(found)
              }
            }
          }
      end
      out << add_endings(output).join('')
      #out << output.join('')
    end
  end

  private

  def log
    @log ||= Logger.new(STDOUT)
  end

  def find_keyword line, keyword, found = []
    log.debug "In #{keyword}"
    prefix = nil
    matched = line.match(/^(\s*)#{keyword} (.+)$/) do |m|
      prefix = m[1] || ''
      datum = m[2]
      log.info "Adding head (#{datum}) for #{keyword}"
      case keyword
      when 'module'
        found << %Q{#{prefix}module #{datum}\n}
      when 'class'
        if datum.match(/<</)
          datum = datum.split(/<</)[1].lstrip
        elsif datum.match(/</)
          datum = datum.split(/</)[0].rstrip
        end
        if datum.match(/\s+/)
          datum = datum.split(/\s+/)[0]
        end
        found << %Q{#{prefix}describe #{datum} do\n}
      when 'def'
        method = datum.split(/(?:\(|\s)/)[0]
        found << %Q{#{prefix}describe "##{method}" do\n}
        found << %Q{#{prefix}#{stub_defs}}
      end
      @keyword_counter += 1
      log.info "Counter: #{@keyword_counter}"
    end

    log.debug "Yielding to block"
    yield(found, prefix) if block_given?

    return found
  end

  def stub_defs
    %Q!  it "should do something useful here"\n!
  end

  def add_endings ar
    prior_prefix, current_prefix = nil, nil
    new_ar = []
    ar.each { |el|
      match = el.match(/^(\s*)/)
      if match
        log.debug("Match: |#{match[1]}|")
        current_prefix = match[1]
      end

      if not prior_prefix.nil? and prior_prefix.length > current_prefix.length
        new_ar += [ "#{current_prefix}end\n", el ]
        @keyword_counter -= 1
        log.info "Counter: #{@keyword_counter}"
      else
        new_ar << el
      end
      prior_prefix = current_prefix
    }

    until @keyword_counter <= 0
      log.debug(@keyword_counter)
      current_prefix = current_prefix[0..-3]
      new_ar << "#{current_prefix}end\n"
      @keyword_counter -= 1
      log.info "Counter: #{@keyword_counter}"
    end
    return new_ar
  end
end

def main
  Find.find(ARGV[0]) do |path|
    base, matched, tail = File.basename(path).partition(/\.rb$/)
    if FileTest.file? path and not File.basename(path).match(/^\./)
      outfile = sprintf('%s/%s/%s_spec.rb', OUTDIR, File.dirname(path), base)
      Rspeccer.new(path, outfile, Logger::INFO).speccify
    end
  end
end

main()
