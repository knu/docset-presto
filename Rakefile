# frozen_string_literal: true
require 'bundler/setup'
Bundler.require

require 'json'
require 'pathname'
require 'tempfile'
require 'uri'
require 'rubygems/version'

def text_node_match(node, pattern)
  case node
  when Nokogiri::XML::Text
    pattern.match(node.text)
  end
end

def between_texts?(node, prev_pattern, next_pattern)
  !!(text_node_match(node.previous, prev_pattern) &&
     text_node_match(node.next, next_pattern))
end

def extract_version
  cd DOCS_ROOT do
    Dir.glob('**/index.html') { |path|
      doc = Nokogiri::HTML(File.read(path), path)
      if version = doc.title[/Presto ([\d.]+)/, 1]
        return version
      end
    }
  end
  nil
end

DOCSET_NAME = 'Presto'
DOCSET = "#{DOCSET_NAME.tr(' ', '_')}.docset"
DOCSET_ARCHIVE = File.basename(DOCSET, '.docset') + '.tgz'
ROOT_RELPATH = 'Contents/Resources/Documents'
INDEX_RELPATH = 'Contents/Resources/docSet.dsidx'
DOCS_ROOT = File.join(DOCSET, ROOT_RELPATH)
DOCS_INDEX = File.join(DOCSET, INDEX_RELPATH)
DOCS_URI = URI("https://trino.io/docs/#{ENV['BUILD_VERSION'] || 'current'}/")
DOCS_DIR = Pathname(DOCS_URI.host + DOCS_URI.path.chomp('/'))
ICON_URL = URI('https://avatars3.githubusercontent.com/u/6882181?v=3&s=64')
ICON_FILE = Pathname('icon.png')
FETCH_LOG = 'wget.log'
DUC_OWNER = 'knu'
DUC_REPO = "git@github.com:#{DUC_OWNER}/Dash-User-Contributions.git"
DUC_OWNER_UPSTREAM = 'Kapeli'
DUC_REPO_UPSTREAM = "https://github.com/#{DUC_OWNER_UPSTREAM}/Dash-User-Contributions.git"
DUC_WORKDIR = File.basename(DUC_REPO, '.git')
DUC_BRANCH = 'presto'

def current_version
  ENV['BUILD_VERSION'] || extract_version()
end

def previous_version
  ENV['PREVIOUS_VERSION'] || Gem::Version.new(current_version).then { |current_version|
    Pathname.glob("versions/*/#{DOCSET}").map { |path|
      Gem::Version.new(path.parent.basename.to_s)
    }.select { |version|
      version < current_version
    }.max&.to_s
  }
end

def previous_docset
  version = previous_version or raise 'No previous version found'

  "versions/#{version}/#{DOCSET}"
end

def built_docset
  if version = ENV['BUILD_VERSION']
    "versions/#{version}/#{DOCSET}"
  else
    DOCSET
  end
end

def wget(*args)
  sh(
    'wget',
    '-nv',
    '--append-output', FETCH_LOG,
    '-N',
    '--retry-on-http-error=500,502,503,504',
    *args
  )
end

desc "Fetch the #{DOCSET_NAME} document files."
task :fetch => %i[fetch:icon fetch:docs]

namespace :fetch do
  task :docs do
    puts 'Downloading %s' % DOCS_URI
    wget '-r', '--no-parent', '-p', DOCS_URI.to_s
  end

  task :icon do
    wget ICON_URL.to_s
    ln ICON_URL.route_from(ICON_URL + './').to_s, ICON_FILE, force: true
  end
end

file DOCS_DIR do
  Rake::Task[:'fetch:docs'].invoke
end

file ICON_FILE do
  Rake::Task[:'fetch:icon'].invoke
end

desc 'Build a docset in the current directory.'
task :build => [DOCS_DIR, ICON_FILE] do |t|
  rm_rf DOCSET

  mkdir_p DOCS_ROOT

  cp 'Info.plist', File.join(DOCSET, 'Contents')
  cp ICON_FILE, DOCSET

  cp_r DOCS_DIR.to_s + '/.', DOCS_ROOT

  # Index
  db = SQLite3::Database.new(DOCS_INDEX)

  db.execute(<<-SQL)
    CREATE TABLE searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT);
    CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path);
  SQL

  insert = db.prepare(<<-SQL)
    INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES (?, ?, ?);
  SQL

  anchor_section = ->(path, node, name) {
    type = 'Section'
    a = Nokogiri::XML::Node.new('a', node.document)
    a['name'] = id = '//apple_ref/cpp/%s/%s' % [type, name].map { |s|
      URI.encode_www_form_component(s).gsub('+', '%20')
    }
    a['class'] = 'dashAnchor'
    node.prepend_child(a)
    # p [path, node.name, name]
  }

  index_item = ->(path, node, type, name) {
    if node
      a = Nokogiri::XML::Node.new('a', node.document)
      a['name'] = id = '//apple_ref/cpp/%s/%s' % [type, name].map { |s|
        URI.encode_www_form_component(s).gsub('+', '%20')
      }
      a['class'] = 'dashAnchor'
      node.prepend_child(a)
      url = "#{path}\##{id}"
    else
      url = path
    end
    insert.execute(name, type, url)
  }

  version = extract_version or raise "Version unknown"

  puts "Generating docset for #{DOCSET_NAME} #{version}"

  cd DOCS_ROOT do
    File.open("_static/presto.css", "a") { |css|
      css.print <<~CSS

        /* Added for docset */
        header {
          display: none;
        }
        .md-main__inner, .md-container, .md-content__inner {
          padding-top: 0px;
        }
        dt:target {
          margin-top: 0px;
          padding-top: 0px;
        }
      CSS
    }

    Dir.glob('**/*.html') { |path|
      doc = Nokogiri::HTML(File.read(path), path)

      doc.css('link[href="https://fonts.gstatic.com/"][rel="preconnect"]').remove
      doc.css('link[href^="https://fonts.googleapis.com/"][rel="stylesheet"]').remove
      doc.css('link[href~="://"]').each { |node|
        warn "#{path} refers to an external resource: #{node.to_s}"
      }

      main = doc.at('article') or next

      if h1 = main.at_css('h1')
        index_item.(path, h1, 'Section', h1.text.chomp('#'))
      end
      main.css('h2, h3').each { |h|
        anchor_section.(path, h, h.text.chomp('#'))
      }

      case path
      when %r{\Afunctions/}
        case File.basename(path, '.html')
        when 'decimal'
          main.css('.literal > .pre').each { |pre|
            case pre.text
            when 'DECIMAL'
              index_item.(path, pre, 'Operator', pre.text)
            end
          }

          main.at('//h2[contains(string(.), " Operator")]/following-sibling::table').css('td:first-of-type .literal > .pre').each { |pre|
            case pre.text
            when %r{\A[+\-*/%]\z}
              index_item.(path, pre, 'Operator', pre.text)
            end
          }
          next
        when 'lambda'
          main.css('.literal > .pre').each { |pre|
            case pre.text
            when '->'
              index_item.(path, pre, 'Operator', pre.text)
            end
          }
        when 'list'
          next
        end

        main.xpath('//h2[contains(string(.), " Operator")]/following-sibling::*').each { |el|
          case el.name
          when 'h1', 'h2'
            break
          when 'table'
            if el.at('//th[string(.) = "Operator"]')
              el.css('td:first-of-type .literal > .pre').each_with_object({}) { |pre, seen|
                op = pre.text
                next if seen[op]

                index_item.(path, pre, 'Operator', op)
                seen[op] = true
              }
            end
          when 'p'
            el.css('.literal > .pre').each { |pre|
              index_item.(path, pre, 'Operator', pre.text)
            }
          end
        }

        main.css('h2').each { |h2|
          case h2.text.chomp('#')
          when /\A(?:[\w ]+: )?(?<operators>(?:(?:(?<op>(?:(?<w>[A-Z]+) )*\g<w>), )*\g<op> and )?\g<op>)\z/
            $~[:operators].scan(/(?<op>(?:(?<w>[A-Z]+) )*\g<w>)/) {
              index_item.(path, h2, 'Operator', $~[:op])
            }
          end
        }
      when %r{\Aconnector/}
        if h = main.at('//h2[contains(string(.), " Properties")]')
          h.xpath('./following-sibling::*').each { |el|
            case el.name
            when 'h1', 'h2'
              break
            when 'table'
              if el.at('//th[string(.) = "Property Name"]')
                el.css('td:first-of-type .literal > .pre').each { |pre|
                  index_item.(path, pre, 'Variable', pre.text)
                }
              end
            end
          }
        end
      when 'language/types.html'
        main.css('h2').each { |h2|
          case text = h2.text.chomp('#')
          when /\A((?<w>[A-Z]+) )*\g<w>\z/
            index_item.(path, h2, 'Type', text)
          end
        }
      when %r{\Asql/}
        main.css('h1').each { |h1|
          case h1.text.chomp('#')
          when /\A(?<st>((?<w>[A-Z]+) )*\g<w>)\z/
            index_item.(path, h1, 'Statement', $~[:st])
          end
        }
        if path == 'sql/select.html'
          main.css('h2, h3').each { |h|
            case h.text.chomp('#')
            when /\A(?<queries>(?:(?<q>(?:(?<w>[A-Z]+) )*\g<w>) \| )*\g<q>)(?: Clause)?\z/
              $~[:queries].scan(/(?<q>(?:(?<w>[A-Z]+) )*\g<w>)/) {
                index_item.(path, h, 'Query', $~[:q])
              }
            end
          }
        end
      end

      main.css('code.descname').each { |descname|
        func = descname.text
        type = 'Function'
        if descclassname = descname.at('./preceding-sibling::*[1][local-name() = "code" and @class = "descclassname" and text()]')
          func = descclassname.text + func
          type = 'Procedure'
        end
        index_item.(path, descname, type, func)
      }

      File.write(path, doc.to_s)
    }
  end

  insert.close

  db.close

  mkdir_p "versions/#{version}/#{DOCSET}"
  sh 'rsync', '-a', '--exclude=.DS_Store', '--delete', "#{DOCSET}/", "versions/#{version}/#{DOCSET}/"

  puts "Finished creating #{DOCSET} #{version}"

  Rake::Task[:diff].invoke
end

task :diff do
  system "rake diff:index diff:docs | #{ENV['PAGER'] || 'more'}"
end

namespace :diff do
  desc 'Show the differences in the index from an installed version.'
  task :index do
    old_index = File.join(previous_docset, INDEX_RELPATH)
    new_index = File.join(built_docset, INDEX_RELPATH)

    begin
      sql = "SELECT name, type, path FROM searchIndex ORDER BY name, type, path"

      odb = SQLite3::Database.new(old_index)
      ndb = SQLite3::Database.new(new_index)

      Tempfile.create(['old', '.txt']) { |otxt|
        odb.execute(sql) { |row|
          otxt.puts row.join("\t")
        }
        odb.close
        otxt.close

        Tempfile.create(['new', '.txt']) { |ntxt|
          ndb.execute(sql) { |row|
            ntxt.puts row.join("\t")
          }
          ndb.close
          ntxt.close

          sh 'diff', '-U3', otxt.path, ntxt.path do
            # ignore status
          end
        }
      }
    ensure
      odb&.close
      ndb&.close
    end
  end

  desc 'Show the differences in the docs from an installed version.'
  task :docs do
    old_root = File.join(previous_docset, ROOT_RELPATH)
    new_root = File.join(built_docset, ROOT_RELPATH)

    sh 'diff', '-rwNU3',
      '-x', '*.js',
      '-x', '*.css',
      '-x', '*.svg',
      '-I', '^[[:space:]]+VERSION:[[:space:]]+\'[0-9.]+\',',
      '-I', 'Presto [0-9]+',
      '-I', '^[[:space:]]*$',
      old_root, new_root do
      # ignore status
    end
  end
end

file DUC_WORKDIR do |t|
  sh 'git', 'clone', DUC_REPO, t.name
  cd t.name do
    sh 'git', 'remote', 'add', 'upstream', DUC_REPO_UPSTREAM
    sh 'git', 'remote', 'update', 'upstream'
  end
end

desc 'Push the generated docset if there is an update'
task :push => DUC_WORKDIR do
  version = extract_version
  workdir = Pathname(DUC_WORKDIR) / 'docsets' / File.basename(DOCSET, '.docset')

  docset_json = workdir / 'docset.json'
  archive = workdir / DOCSET_ARCHIVE
  versioned_archive = workdir / 'versions' / version / DOCSET_ARCHIVE

  puts "Resetting the working directory"
  cd workdir.to_s do
    sh 'git', 'remote', 'update'
    sh 'git', 'rev-parse', '--verify', '--quiet', DUC_BRANCH do |ok, |
      if ok
        sh 'git', 'checkout', DUC_BRANCH
        sh 'git', 'reset', '--hard', 'upstream/master' unless ENV['NO_RESET']
      else
        sh 'git', 'checkout', '-b', DUC_BRANCH, 'upstream/master'
      end
    end
  end

  sh 'tar', '-zcf', DOCSET_ARCHIVE, '--exclude=.DS_Store', DOCSET
  mv DOCSET_ARCHIVE, archive
  mkdir_p versioned_archive.dirname
  cp archive, versioned_archive

  puts "Updating #{docset_json}"
  File.open(docset_json, 'r+') { |f|
    json = JSON.parse(f.read)
    json['version'] = version
    specific_version = {
      'version' => version,
      'archive' => versioned_archive.relative_path_from(workdir).to_s
    }
    json['specific_versions'] = [specific_version] | json['specific_versions']
    f.rewind
    f.puts JSON.pretty_generate(json, indent: "    ")
    f.truncate(f.tell)
  }

  cd workdir.to_s do
    sh 'git', 'diff', '--exit-code', docset_json.relative_path_from(workdir).to_s do |ok, _res|
      if ok
        puts "Nothing to commit."
      else
        sh 'git', 'add', *[archive, versioned_archive, docset_json].map { |path|
          path.relative_path_from(workdir).to_s
        }
        sh 'git', 'commit', '-m', "Update #{DOCSET_NAME} docset to #{version}"
        sh 'git', 'push', '-fu', 'origin', "#{DUC_BRANCH}:#{DUC_BRANCH}"
      end
    end
  end
end

desc 'Send a pull-request'
task :pr => DUC_WORKDIR do
  cd DUC_WORKDIR do
    sh 'git', 'diff', '--exit-code', '--stat', "#{DUC_BRANCH}..upstream/master" do |ok, _res|
      if ok
        puts "Nothing to send a pull-request for."
      else
        sh 'hub', 'pull-request', '-b', "#{DUC_OWNER_UPSTREAM}:master", '-h', "#{DUC_OWNER}:#{DUC_BRANCH}", '-m', `git log -1 --pretty=%s #{DUC_BRANCH}`.chomp
      end
    end
  end
end

desc 'Delete all fetched files and generated files'
task :clean do
  rm_rf [DOCS_DIR, ICON_FILE, DOCSET, DOCSET_ARCHIVE, FETCH_LOG]
end

task :default => :build
