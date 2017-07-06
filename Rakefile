# frozen_string_literal: true
require 'bundler/setup'
Bundler.require

require 'json'
require 'pathname'
require 'uri'

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

def extract_version(doc)
  doc.title[/Presto ([\d.]+)/, 1]
end

DOCSET_NAME = 'Presto'
DOCSET = "#{DOCSET_NAME.tr(' ', '_')}.docset"
DOCSET_ARCHIVE = File.basename(DOCSET, '.docset') + '.tgz'
DOCS_URI = URI('https://prestodb.io/docs/current/')
DOCS_DIR = Pathname(DOCS_URI.host + DOCS_URI.path.chomp('/'))
ICON_FILE = Pathname('icon.png')
FETCH_LOG = 'wget.log'
DUC_REPO = 'git@github.com:knu/Dash-User-Contributions.git'
DUC_REPO_UPSTREAM = 'https://github.com/Kapeli/Dash-User-Contributions.git'
DUC_WORKDIR = File.basename(DUC_REPO, '.git')
DUC_BRANCH = 'presto'

desc "Fetch the #{DOCSET_NAME} document files."
task :fetch => [DOCS_DIR, ICON_FILE]

file DOCS_DIR do |t|
  puts 'Downloading %s' % DOCS_URI
  sh 'wget', '-nv', '--append-output', FETCH_LOG, '-r', '--no-parent', '-nc', '-p', DOCS_URI.to_s
end

file ICON_FILE do |t|
  sh 'wget', '-nv', '--append-output', FETCH_LOG, '-O', t.name, '-nc', 'https://avatars3.githubusercontent.com/u/6882181?v=3&s=64'
end

desc 'Build a docset in the current directory.'
task :build => :fetch do |t|
  target = DOCSET
  docdir = File.join(target, 'Contents/Resources/Documents')

  rm_rf target

  mkdir_p docdir

  cp 'Info.plist', File.join(target, 'Contents')
  cp ICON_FILE, target

  cp_r DOCS_DIR.to_s + '/.', docdir

  # Index
  db = SQLite3::Database.new(File.join(target, 'Contents/Resources/docSet.dsidx'))

  db.execute(<<-SQL)
    CREATE TABLE searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT);
    CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path);
  SQL

  insert = db.prepare(<<-SQL)
    INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES (?, ?, ?);
  SQL

  anchor_section = ->(path, node, name) {
    type = 'Section'.freeze
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

  add_operators = ->(section) {
    path = section.document.url
    section.css('.literal > .pre').each { |pre|
      if !pre.at('./preceding-sibling::*') && (
           pre.at('./ancestor::td[not(./preceding-sibling::td)]') ||
           between_texts?(pre.parent, /\AThe \z/, /\A operator /) ||
           between_texts?(pre.parent, / expressions are written with \z/, /\A:/)  # Lambda Expression
         )
        index_item.(path, pre, 'Operator', pre.text)
      end
    }
  }

  puts 'Indexing documents'

  cd docdir do
    Dir.glob('**/*.html') { |path|
      doc = Nokogiri::HTML(File.read(path), path)

      if h1 = doc.at_css('.content h1')
        case title = h1.text
        when /\A[\d\.]+ /
          index_item.(path, h1, 'Section', title)
        end
      end
      doc.css('.content h2, .content h3').each { |h|
        anchor_section.(path, h, h.text)
      }

      case path
      when 'index.html'
        puts "Generating docset for #{DOCSET_NAME} #{extract_version(doc)}"
      when %r{\Afunctions/}
        if section = doc.at('h1 + .section[id]')
          add_operators.(section)
        end
        doc.xpath('//*[@class = "content"]//h2[not(../dl[@class = "function"])]').each { |h2|
          case h2.text
          when /\A(?:[\w ]+: )?(?<operators>(?:(?:(?<op>(?:(?<w>[A-Z]+) )*\g<w>), )*\g<op> and )?\g<op>)\z/
            $~[:operators].scan(/(?<op>(?:(?<w>[A-Z]+) )*\g<w>)/) {
              index_item.(path, h2, 'Operator', $~[:op])
            }
          end
        }
      when %r{\Aconnector/}
        doc.css('.content h3 > .literal > .pre').each { |pre|
          if pre.parent.parent.children.size == 1
            index_item.(path, pre, 'Variable', pre.text)
          end
        }
      when 'language/types.html'
        doc.css('.content h2').each { |h2|
          case text = h2.text
          when /\A((?<w>[A-Z]+) )*\g<w>\z/
            index_item.(path, h2, 'Type', text)
          end
        }
      when %r{\Asql/}
        doc.css('.content h1').each { |h1|
          case h1.text
          when /\A[\d\.]+ (?<st>((?<w>[A-Z]+) )*\g<w>)\z/
            index_item.(path, h1, 'Statement', $~[:st])
          end
        }
        if path == 'sql/select.html'
          doc.css('.content h2, .content h3').each { |h|
            case h.text
            when /\A(?<queries>(?:(?<q>(?:(?<w>[A-Z]+) )*\g<w>) \| )*\g<q>)(?: Clause)?\z/
              $~[:queries].scan(/(?<q>(?:(?<w>[A-Z]+) )*\g<w>)/) {
                index_item.(path, h, 'Query', $~[:q])
              }
            end
          }
        end
      end

      doc.css('code.descname').each { |descname|
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
  version = extract_version(Nokogiri::HTML(File.read(File.join(DOCSET, 'Contents/Resources/Documents/index.html'))))
  workdir = Pathname(DUC_WORKDIR) / 'docsets' / File.basename(DOCSET, '.docset')

  docset_json = workdir / 'docset.json'
  archive = workdir / DOCSET_ARCHIVE
  versioned_archive = workdir / 'versions' / version / DOCSET_ARCHIVE

  puts "Resetting the working directory"
  cd workdir.to_s do
    sh 'git', 'remote', 'update'
    sh 'git', 'checkout', DUC_BRANCH
    sh 'git', 'reset', '--hard', 'upstream/master'
  end

  sh 'tar', '-zcf', DOCSET_ARCHIVE, '--exclude=.DS_Store', DOCSET and
    mv DOCSET_ARCHIVE, archive and
    mkdir_p versioned_archive.dirname and
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
        sh 'git', 'push', '-f', 'origin', DUC_BRANCH
      end
    end
  end
end

desc 'Delete all fetched files and generated files'
task :clean do
  rm_rf [DOCS_DIR, ICON_FILE, DOCSET, DOCSET_ARCHIVE, FETCH_LOG]
end

task :default => :build
