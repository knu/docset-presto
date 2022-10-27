# frozen_string_literal: true
require 'bundler/setup'
Bundler.require

require 'json'
require 'pathname'
require 'tempfile'
require 'uri'
require 'rubygems/version'

def jenkins?
  /jenkins-/.match?(ENV['BUILD_TAG'])
end

def paginate_command(cmd, diff: false)
  case cmd
  when Array
    cmd = cmd.shelljoin
  end

  if $stdout.tty? || (diff && jenkins?)
    pager = (ENV['DIFF_PAGER'] if diff) || ENV['PAGER'] || 'more'
    "#{cmd} | #{pager}"
  else
    cmd
  end
end

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
DOCS_URI = URI("https://prestodb.io/docs/#{ENV['BUILD_VERSION'] || 'current'}/")
DOCS_DIR = Pathname(DOCS_URI.host + DOCS_URI.path.chomp('/'))
ICON_URL = URI('https://avatars.githubusercontent.com/u/6882181?v=4&s=64')
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

def dump_index(docset, out)
  index = File.join(docset, INDEX_RELPATH)

  SQLite3::Database.new(index) do |db|
    db.execute("SELECT name, type, path FROM searchIndex ORDER BY name, type, path") do |row|
      out.puts row.join("\t")
    end
  end

  out.flush
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
  rm_rf [DOCSET, DOCSET_ARCHIVE]

  mkdir_p DOCS_ROOT

  cp 'Info.plist', File.join(DOCSET, 'Contents')
  cp ICON_FILE, DOCSET

  cp_r DOCS_DIR.to_s + '/.', DOCS_ROOT

  # Index
  db = SQLite3::Database.new(DOCS_INDEX)

  db.execute(<<-SQL)
    CREATE TABLE searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT);
  SQL
  db.execute(<<-SQL)
    CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path);
  SQL

  insert = db.prepare(<<-SQL)
    INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES (?, ?, ?);
  SQL

  select = db.prepare(<<-SQL)
    SELECT TRUE FROM searchIndex where type = ? AND name = ?;
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

  has_item = ->(type, name) {
    !select.execute!(type, name).empty?
  }

  in_procedures_section = ->(node) {
    node.xpath('./ancestor::section[contains(@id, "procedures")]').size > 0
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
        when 'conditional'
          main.css('h2').each { |h|
            title = h.text.chomp('#')
            if h.at_xpath("./following-sibling::*[1]/code[string(.) = '#{title}' and starts-with(normalize-space(./following-sibling::text()[1]), 'expression ')]")
              case title
              when 'CASE'
                index_item.(path, h, 'Query', title)
              else
                raise "Unknown expression: #{title}"
              end
            end
          }
        when 'decimal'
          main.css('.literal > .pre').each { |pre|
            case pre.text
            when 'DECIMAL'
              index_item.(path, pre, 'Operator', pre.text)
            end
          }

          main.at('.//h2[contains(translate(., "O", "o"), " operator")]/following-sibling::table').css('td:first-of-type .literal > .pre').each { |pre|
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

        main.xpath('.//h2[contains(translate(., "O", "o"), " operator")]').each { |h|
          h.xpath('./following-sibling::*').each { |el|
            case el.name
            when 'h1', 'h2'
              break
            when 'table'
              if el.at('.//th[string(.) = "Operator"]')
                el.css('td:first-of-type .literal > .pre').each_with_object({}) { |pre, seen|
                  op = pre.text
                  next if seen[op]

                  index_item.(path, pre, 'Operator', op)
                  seen[op] = true
                }
              end
            when 'p'
              el.css('.literal').each { |literal|
                case op = literal.text.gsub(/\s+/, ' ')
                when /\A(?:NULL|TRUE|FALSE)\z|\A[a-z]/
                  # ignore
                else
                  index_item.(path, literal, 'Operator', op)
                end
              }
            end
          }
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
        if h = main.at('.//h2[contains(translate(., "P", "p"), " properties")]')
          h.xpath('./following-sibling::*').each { |el|
            case el.name
            when 'h1', 'h2'
              break
            when 'table'
              if el.at('.//th[translate(., "NP", "np") = "property name"]')
                el.css('td:first-of-type .literal > .pre').each { |pre|
                  index_item.(path, pre, 'Variable', pre.text)
                }
              end
            end
          }
        end
        main.css('li .highlight-sql pre').each { |pre|
          if procedure = pre.text[/\A(?:CALL\s+)?\K[^(]+/]
            li = pre.at_xpath('(./ancestor::li)[1]') or next
            index_item.(path, li, 'Procedure', procedure)
          end
        }
      when 'language/types.html'
        main.css('h3 > code').each { |code|
          case text = code.text.chomp('#')
          when /\A(?<w>[A-Z][A-Za-z0-9]*(\(P\))?)( \g<w>)*\z/
            index_item.(path, code.parent, 'Type', text)
          else
            raise "Unknown type name: #{text}"
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

      if h = main.at_css('h2#procedures')
        el = h
        while el = el.next_element
          case el.name
          when /\Ah[1-6]\z/
            break if el.name <= h.name
          when 'ul'
            el.xpath('./li/p[position() = 1]/code[position() = 1]').each do |para|
              if procedure = para.text[/\A(?:CALL\s+)?\K[^(]+/]
                index_item.(path, el, 'Procedure', procedure)
              end
            end
          end
        end
      end

      main.css('.descname').each { |descname|
        func =
          if (prev = descname.previous).matches?('.descclassname')
            prev.text + descname.text
          else
            descname.text
          end
        type =
          if in_procedures_section.(descname)
            'Procedure'
          else
            'Function'
          end
        index_item.(path, descname, type, func)
      }

      File.write(path, doc.to_s)
    }
  end

  select.close
  insert.close

  get_count = ->(**criteria) do
    db.get_first_value(<<-SQL, criteria.values)
      SELECT COUNT(*) from searchIndex where #{
        criteria.each_key.map { |column| "#{column} = ?" }.join(' and ')
      }
    SQL
  end

  assert_exists = ->(**criteria) do
    if get_count.(**criteria).zero?
      raise "#{criteria.inspect} not found in index!"
    end
  end

  puts 'Performing sanity check'

  {
    'Statement' => ['SELECT', 'INSERT', 'DELETE',  # There's no UPDATE in Presto DB.
                    'SHOW CREATE FUNCTION'],
    'Query' => ['CROSS JOIN',
                'UNION', 'INTERSECT', 'EXCEPT',
                'GROUP BY', 'LIMIT', 'OFFSET',
                'IN', 'EXISTS', 'UNNEST',
                'CASE'],
    'Function' => ['count', 'merge',
                   'array_sort', 'rank',
                   'if', 'coalesce', 'nullif'],
    'Procedure' => ['runtime.kill_query',
                    'kudu.system.add_range_partition',
                    'kudu.system.drop_range_partition',
                    'system.create_empty_partition',
                    'system.sync_partition_metadata'],
    'Type' => ['BOOLEAN', 'BIGINT', 'DOUBLE', 'DECIMAL', 'VARCHAR', 'VARBINARY',
               'DATE', 'TIMESTAMP', 'TIMESTAMP WITH TIME ZONE',
               'ARRAY', 'UUID', 'HyperLogLog'],
    'Operator' => ['+', '<=', '!=', '<>', '[]', '||',
                   'BETWEEN', 'NOT BETWEEN', 'LIKE', 'AND', 'OR', 'NOT',
                   'ANY', 'IS NULL', 'IS DISTINCT FROM'],
    'Section' => ['BigQuery Connector']
  }.each { |type, names|
    names.each { |name|
      assert_exists.(name: name, type: type)
    }
  }

  db.close

  sh 'tar', '-zcf', DOCSET_ARCHIVE, '--exclude=.DS_Store', DOCSET

  mkdir_p "versions/#{version}/#{DOCSET}"
  sh 'rsync', '-a', '--exclude=.DS_Store', '--delete', "#{DOCSET}/", "versions/#{version}/#{DOCSET}/"

  puts "Finished creating #{DOCSET} #{version}"

  system paginate_command('rake diff:index', diff: true)
end

task :dump do
  system paginate_command('rake dump:index')
end

namespace :dump do
  desc 'Dump the index.'
  task :index do
    dump_index(built_docset, $stdout)
  end
end

task :diff do
  system paginate_command('rake diff:index diff:docs', diff: true)
end

namespace :diff do
  desc 'Show the differences in the index from an installed version.'
  task :index do
    Tempfile.create(['old', '.txt']) do |otxt|
      Tempfile.create(['new', '.txt']) do |ntxt|
        dump_index(previous_docset, otxt)
        otxt.close
        dump_index(built_docset, ntxt)
        ntxt.close

        puts "Diff in document indexes:"
        sh 'diff', '-U3', otxt.path, ntxt.path do
          # ignore status
        end
      end
    end
  end

  desc 'Show the differences in the docs from an installed version.'
  task :docs do
    old_root = File.join(previous_docset, ROOT_RELPATH)
    new_root = File.join(built_docset, ROOT_RELPATH)

    puts "Diff in document files:"
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

  cp DOCSET_ARCHIVE, archive
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
    json_path = docset_json.relative_path_from(workdir).to_s

    if system(*%W[git diff --exit-code --quiet #{json_path}])
      puts "Nothing to commit."
      next
    end

    sh paginate_command(%W[git diff #{json_path}], diff: true)

    sh 'git', 'add', *[archive, versioned_archive, docset_json].map { |path|
      path.relative_path_from(workdir).to_s
    }
    sh 'git', 'commit', '-m', "Update #{DOCSET_NAME} docset to #{version}"
    sh 'git', 'push', '-fu', 'origin', "#{DUC_BRANCH}:#{DUC_BRANCH}"

    puts "New docset is committed and pushed to #{DUC_OWNER}:#{DUC_BRANCH}.  To send a PR, go to the following URL:"
    puts "\t" + "#{DUC_REPO_UPSTREAM.delete_suffix(".git")}/compare/master...#{DUC_OWNER}:#{DUC_BRANCH}?expand=1"
  end
end

desc 'Send a pull-request'
task :pr => DUC_WORKDIR do
  cd DUC_WORKDIR do
    sh(*%W[git diff --exit-code --stat #{DUC_BRANCH}..upstream/master]) do |ok, _res|
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
