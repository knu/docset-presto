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

def capture(*args)
  `#{args.flatten.shelljoin}`
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

def git_ref_exists?(ref)
  system(*%W[git show-ref --quiet origin/#{DUC_BRANCH}])
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

def existing_pull_url
  repo = "#{DUC_OWNER_UPSTREAM}/#{DUC_REPO}"
  query = "repo:#{repo} is:pr author:#{DUC_OWNER} head:#{DUC_BRANCH} is:open"
  graphql = <<~GRAPHQL
    query($q: String!) {
      search(
        query: $q
        type: ISSUE
        last: 1
      ) {
        edges {
          node {
            ... on PullRequest {
              number
              url
              headRepository {
                nameWithOwner
              }
              headRefName
            }
          }
        }
      }
    }
  GRAPHQL
  jq = '.data.search.edges.[0].node.url'

  IO.popen(%W[gh api graphql -f q=#{query} -f query=#{graphql} --jq=#{jq}]) { |io|
    io.read.chomp[%r{\Ahttps://.*}]
  }
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
COMMON_CSS = Pathname('common.css')
COMMON_CSS_URL = DOCS_URI + COMMON_CSS.to_s
FETCH_LOG = 'wget.log'
DUC_REPO = 'Dash-User-Contributions'
DUC_OWNER = 'knu'
DUC_REMOTE_URL = "git@github.com:#{DUC_OWNER}/#{DUC_REPO}.git"
DUC_OWNER_UPSTREAM = 'Kapeli'
DUC_REMOTE_URL_UPSTREAM = "https://github.com/#{DUC_OWNER_UPSTREAM}/#{DUC_REPO}.git"
DUC_WORKDIR = DUC_REPO
DUC_DEFAULT_BRANCH = 'master'
DUC_BRANCH = 'presto'

URI_ATTRS = [
  ['a', 'href'],
  ['img', 'src'],
  ['link', 'href'],
  ['script', 'src'],
  ['iframe', 'src'],
]

def duc_versions(ref)
  Rake::Task[DUC_WORKDIR].invoke

  cd Pathname(DUC_WORKDIR) do
    docset_json = Pathname('docsets') / File.basename(DOCSET, '.docset') / 'docset.json'

    JSON.parse(
      capture(*%W[git cat-file -p #{ref}:#{docset_json}])
    )['specific_versions'].map { |o| o['version'] }
  end
end

def current_version
  ENV['BUILD_VERSION'] || extract_version()
end

def previous_version
  case version = ENV['PREVIOUS_VERSION']
  when nil, ''
    Gem::Version.new(current_version).then { |current_version|
      Pathname.glob("versions/*/#{DOCSET}").map { |path|
        Gem::Version.new(path.parent.basename.to_s)
      }.select { |version|
        version < current_version
      }.max&.to_s
    }
  when 'published'
    duc_versions("upstream/#{DUC_DEFAULT_BRANCH}").first
  else
    version
  end
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
    '--reject-regex=/_static/$',
    '--reject-regex=/installation/cli\.html$',
    *args
  )
end

desc "Fetch the #{DOCSET_NAME} document files."
task :fetch => %i[fetch:icon fetch:docs]

namespace :fetch do
  task :docs do
    puts 'Building %s locally' % DOCS_URI
    sh './build-docs.sh', ENV['BUILD_VERSION'] || 'current'
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

  resolve_url = ->(href, uri) do
    begin
      case abs = uri + href
      when URI::HTTP
        # ok
      else
        return href
      end
    rescue URI::Error => e
      case href
      when /\Adata:/, /\Amailto:/
        return href
      end
      warn e.message
      return href
    end

    rel = DOCS_URI.route_to(abs)

    if !rel.host && !rel.path.start_with?("../") && File.file?(rel.path)
      return uri.route_to(abs)
    end

    abs
  end

  bad_hrefs = Set[]

  class SectionSections
    def initialize(content)
      @sections = content.css('h1, h2, h3, h4, h5, h6').to_a
    end

    include Enumerable

    def each(query = nil, &)
      return to_enum(__method__, query) unless block_given?

      if query
        @sections.each do |section|
          yield section if section.matches?(query)
        end
      else
        @sections.each(&)
      end
    end

    def in_section?(node, id_substr)
      current_level = nil

      @sections.reverse_each do |section|
        next if (section <=> node)&.positive?

        name = section.name
        next if current_level&.>= name

        current_level = name
        return true if section['id']&.include?(id_substr)
      end

      false
    end
  end

  version = extract_version or raise "Version unknown"

  puts "Generating docset for #{DOCSET_NAME} #{version}"

  cd DOCS_ROOT do
    COMMON_CSS.write(
      <<~CSS

        /* Added for docset */
        .md-main__inner, .md-container, .md-content__inner {
          padding-top: 0px;
        }
        dt:target {
          margin-top: 0px;
          padding-top: 0px;
        }
      CSS
    )

    Dir.glob('**/*.html') do |path|
      uri = DOCS_URI + path
      doc = Nokogiri::HTML(File.read(path), path)

      doc.css('header, footer, [data-md-component="sidebar"], [data-md-component="skip"], #__drawer, #__search, a[title^="Edit "]').remove
      doc.css('.headerlink').remove

      doc.css('link[href="https://fonts.gstatic.com/"][rel="preconnect"]').remove
      doc.css('link[href^="https://fonts.googleapis.com/"][rel="stylesheet"]').remove

      URI_ATTRS.each do |tag, attr|
        doc.css("#{tag}[#{attr}]").each do |e|
          e[attr] = resolve_url.(e[attr], uri)
        end
      end

      doc.css('link[href~="://"]').each { |node|
        warn "#{path} refers to an external resource: #{node.to_s}"
      }

      doc.at('head') << Nokogiri::XML::Node.new('link', doc).tap { |link|
        link['rel'] = 'stylesheet'
        link['href'] = uri.route_to(COMMON_CSS_URL)
      }

      main = doc.at('article') or next
      sections = SectionSections.new(main)

      if h1 = sections.find { |h| h.name == 'h1' }
        index_item.(path, h1, 'Section', h1.text)
      end
      sections.each('h2, h3') do |h|
        anchor_section.(path, h, h.text)
      end

      case path
      when %r{\Afunctions/}
        case File.basename(path, '.html')
        when 'conditional'
          main.css('h2').each { |h|
            title = h.text
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
          case h2.text
          when /\A(?:[\w ]+: )?(?<operators>(?:(?:(?<op>(?:(?<w>[A-Z]+) )*\g<w>), )*\g<op> and )?\g<op>)\z/
            $~[:operators].scan(/(?<op>(?:(?<w>[A-Z]+) )*\g<w>)/) {
              index_item.(path, h2, 'Operator', $~[:op])
            }
          end
        }
      when %r{\Aconnector/}
        connector_name = main.xpath('//pre').find { |pre|
          if name = pre.xpath('normalize-space(.)')[/^connector.name=\K\w+/]
            break name
          end
        }
        get_connector_name =
          -> { connector_name or raise "#{path}: connector.name not found" }

        [
          *main.css("h2, h3").select { |h|
            h.text.match?(/ (Properties|Authentication)/i)
          },
          *main.css('h2#configuration'),
        ].each do |h|
          h.xpath('./following-sibling::*').each { |el|
            case el.name
            when 'h1', 'h2'
              break
            when 'table'
              if el.at('.//th[translate(., "NP", "np") = "property name"]')
                el.css('td:first-of-type .literal > .pre').each { |pre|
                  case var = pre.text
                  when /\A([\w-]+)\./
                    connector_name ||= $1
                  end

                  index_item.(path, pre, 'Variable', var)
                }
              end
            end
          }
        end

        main.css('li .highlight-sql pre').each { |pre|
          if procedure = pre.text[/\A(?:CALL\s+)?\K[^(]+/]
            li = pre.at_xpath('(./ancestor::li)[1]') or next
            index_item.(path, li, 'Procedure', procedure.sub(/\A<[^.>]+>(?=\.)/, get_connector_name.call))
          end
        }

        if h = main.at_css('h2#procedures')
          el = h
          while el = el.next_element
            case el.name
            when /\Ah[1-6]\z/
              break if el.name <= h.name
            when 'ul'
              el.xpath('./li/p[position() = 1]/code[position() = 1]').each do |para|
                if procedure = para.text[/\A(?:CALL\s+)?\K[^(]+/]
                  index_item.(path, el, 'Procedure', "#{get_connector_name.call}.#{procedure}")
                end
              end
            end
          end
        end
      when 'language/types.html'
        main.css('h3 > code').each { |code|
          case text = code.text
          when /\A(?<w>[A-Z][A-Za-z0-9]*(\(P\))?)( \g<w>)*\z/
            index_item.(path, code.parent, 'Type', text)
          else
            raise "Unknown type name: #{text}"
          end
        }
      when %r{\Asql/}
        main.css('h1').each { |h1|
          case h1.text
          when /\A(?<st>((?<w>[A-Z]+) )*\g<w>)\z/
            index_item.(path, h1, 'Statement', $~[:st])
          end
        }
        if path == 'sql/select.html'
          main.css('h2, h3').each { |h|
            case h.text
            when /\A(?<queries>(?:(?<q>(?:(?<w>[A-Z]+) )*\g<w>) \| )*\g<q>)(?: Clause)?\z/
              $~[:queries].scan(/(?<q>(?:(?<w>[A-Z]+) )*\g<w>)/) {
                index_item.(path, h, 'Query', $~[:q])
              }
            end
          }
        end
      end

      main.css('.function .sig').each { |sig|
        func = sig.text.strip[/\A(?:[A-Z]+ )?[^\s\(]+/]
        type =
          if sections.in_section?(sig, 'procedures')
            'Procedure'
          else
            'Function'
          end
        index_item.(path, sig, type, func)
      }
    ensure
      File.write(path, doc.to_s)
    end
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
                    'hive.system.create_empty_partition',
                    'hive.system.sync_partition_metadata'],
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
  sh 'git', 'clone', DUC_REMOTE_URL, t.name
  cd t.name do
    sh 'git', 'remote', 'add', 'upstream', DUC_REMOTE_URL_UPSTREAM
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

    start_ref =
      if git_ref_exists?("origin/#{DUC_BRANCH}")
        "origin/#{DUC_BRANCH}"
      else
        "upstream/#{DUC_DEFAULT_BRANCH}"
      end
    if git_ref_exists?(DUC_BRANCH)
      sh 'git', 'checkout', DUC_BRANCH
      sh 'git', 'reset', '--hard', start_ref
    else
      sh 'git', 'checkout', '-b', DUC_BRANCH, start_ref
    end
  end

  base_versions = duc_versions("upstream/#{DUC_DEFAULT_BRANCH}")
  head_versions = duc_versions("HEAD")

  cd workdir.to_s do
    if (head_versions - base_versions - [version]).empty?
      sh 'git', 'reset', '--hard', "upstream/#{DUC_DEFAULT_BRANCH}"
    end
  end

  cp DOCSET_ARCHIVE, archive
  mkdir_p versioned_archive.dirname
  cp archive, versioned_archive

  puts "Updating #{docset_json}"
  updated = false
  File.open(docset_json, 'r+') { |f|
    json = JSON.parse(f.read)
    json['specific_versions'] = specific_versions = json['specific_versions'].to_set.add(
      {
        'version' => version,
        'archive' => versioned_archive.relative_path_from(workdir).to_s
      }
    ).sort_by { |o| Gem::Version.new(o['version']) }.reverse
    latest_version = specific_versions.dig(0, 'version')
    updated = json['version'] != latest_version
    json['version'] = latest_version
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

    sh(*%W[git add], *[archive, versioned_archive, docset_json].map { |path| path.relative_path_from(workdir).to_s })
    message =
      if updated
        "Update #{DOCSET_NAME} docset to #{version}"
      else
        "Add #{DOCSET_NAME} docset #{version}"
      end
    sh(*%W[git commit -m #{message}])
    sh(*%W[git push -fu origin #{DUC_BRANCH}:#{DUC_BRANCH}])

    if pull_url = existing_pull_url
      puts "Updating the title of the existing pull-request: #{pull_url}"
      sh(*%W[gh pr edit #{pull_url} --title #{message}])
    end
  end

  unless `git tag -l v#{version}`.empty?
    sh(*%W[git tag -d v#{version}]) {}
    sh(*%W[gh release delete --cleanup-tag --yes v#{version}]) {}
  end

  sh(*%W[gh release create v#{version} -t v#{version} -n #{<<~NOTES} -- #{archive}])
    This docset is generated from the official documentation of Presto.

    #{DOCS_URI}

    Copyright The Presto Foundation. All rights reserved. Presto is a registered trademark of LF Projects, LLC.
  NOTES

  puts "New docset is committed and pushed to #{DUC_OWNER}:#{DUC_BRANCH}.  To send a PR, go to the following URL:"
  puts "\t" + "#{DUC_REMOTE_URL_UPSTREAM.delete_suffix(".git")}/compare/#{DUC_DEFAULT_BRANCH}...#{DUC_OWNER}:#{DUC_BRANCH}?expand=1"
end

desc 'Send a pull-request'
task :pr => DUC_WORKDIR do
  cd DUC_WORKDIR do
    sh(*%W[git diff --exit-code --stat #{DUC_BRANCH}..upstream/#{DUC_DEFAULT_BRANCH}]) do |ok, _res|
      if ok
        puts "Nothing to send a pull-request for."
      else
        sh(*%W[gh repo set-default #{DUC_OWNER_UPSTREAM}/#{DUC_REPO}])
        sh(*%W[
          gh pr create
          --base #{DUC_DEFAULT_BRANCH}
          --head #{DUC_OWNER}:#{DUC_BRANCH}
          --title #{capture(*%W[git log -1 --pretty=%s #{DUC_BRANCH}]).chomp}
        ])
      end
    end
  end
end

desc 'Delete all fetched files and generated files'
task :clean do
  rm_rf [DOCS_DIR, ICON_FILE, DOCSET, DOCSET_ARCHIVE, FETCH_LOG]
end

task :default => :build
