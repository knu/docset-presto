# frozen_string_literal: true
require 'bundler/setup'
Bundler.require

require 'pathname'
require 'uri'

def doclink(url, anchor = nil)
  URI(url.to_s).tap { |uri|
    uri.fragment = URI.encode_www_form_component(anchor) if anchor
  }
end

def find_anchor(node)
  node.at_xpath('(./ancestor::*[@id][1]/@id | ./preceding::*[@id][1]/@id | ./self::*[@id]/@id)[last()]')&.value
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

DOCSET = 'Presto.docset'
DOCSET_ARCHIVE = File.basename(DOCSET, '.docset') + '.tgz'
DOCS_URI = URI('https://prestodb.io/docs/current/')
DOCS_DIR = Pathname(DOCS_URI.host + DOCS_URI.path.chomp('/'))
ICON_FILE = Pathname('icon.png')

desc 'Fetch the Presto document zip file.'
task :fetch do |t|
  unless DOCS_DIR.directory?
    puts 'Downloading %s' % DOCS_URI
    system 'wget', '-nv', '-o', 'wget.log', '-r', '--no-parent', '-nc', '-p', DOCS_URI.to_s
  end

  unless ICON_FILE.file?
    system 'wget', '-nv', '-o', 'wget.log', '-O', ICON_FILE.to_s, '-nc', 'https://avatars3.githubusercontent.com/u/6882181?v=3&s=64'
  end
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

  add_operators = ->(section) {
    path = section.document.url
    section.css('.literal > .pre').each { |pre|
      if !pre.at('./preceding-sibling::*') && (
           pre.at('./ancestor::td[not(./preceding-sibling::td)]') ||
           between_texts?(pre.parent, /\AThe \z/, /\A operator /) ||
           between_texts?(pre.parent, / expressions are written with \z/, /\A:/)  # Lambda Expression
         )
        name = pre.text
        uri = doclink(path, find_anchor(pre))
        insert.execute(name, 'Operator', uri.to_s)
      end
    }
  }

  puts 'Indexing documents'

  Dir.chdir(docdir) {
    Dir.glob('**/*.html') { |path|
      doc = Nokogiri::HTML(File.read(path), path)

      if h1 = doc.at_css('.content h1')
        case title = h1.text
        when /\A[\d\.]+ /
          uri = doclink(path, find_anchor(h1))
          insert.execute(title, 'Section', uri.to_s)
        end
      end

      case path
      when %r{\Afunctions/}
        if section = doc.at('h1 + .section[id]')
          add_operators.(section)
        end
        doc.xpath('//*[@class = "content"]//h2[not(../dl[@class = "function"])]').each { |h2|
          case h2.text
          when /\A(?:[\w ]+: )?(?<operators>(?:(?:(?<op>(?:(?<w>[A-Z]+) )*\g<w>), )*\g<op> and )?\g<op>)\z/
            $~[:operators].scan(/(?<op>(?:(?<w>[A-Z]+) )*\g<w>)/) {
              uri = doclink(path, find_anchor(h2))
              insert.execute($~[:op], 'Operator', uri.to_s)
            }
          end
        }
      when %r{\Aconnector/}
        doc.css('.content h3 > .literal > .pre').each { |pre|
          if pre.parent.parent.children.size == 1
            uri = doclink(path, find_anchor(pre))
            insert.execute(pre.text, 'Variable', uri.to_s)
          end
        }
      when 'language/types.html'
        doc.css('.content h2').each { |h2|
          case text = h2.text
          when /\A((?<w>[A-Z]+) )*\g<w>\z/
            uri = doclink(path, find_anchor(h2))
            insert.execute(text, 'Type', uri.to_s)
          end
        }
      when %r{\Asql/}
        doc.css('.content h1').each { |h1|
          case h1.text
          when /\A[\d\.]+ (?<st>((?<w>[A-Z]+) )*\g<w>)\z/
            st = $~[:st]
            uri = doclink(path, find_anchor(h1))
            insert.execute(st, 'Statement', uri.to_s)
          end
        }
        if path == 'sql/select.html'
          doc.css('.content h2, .content h3').each { |h|
            case h.text
            when /\A(?<queries>(?:(?<q>(?:(?<w>[A-Z]+) )*\g<w>) \| )*\g<q>)(?: Clause)?\z/
              $~[:queries].scan(/(?<q>(?:(?<w>[A-Z]+) )*\g<w>)/) {
                uri = doclink(path, find_anchor(h))
                insert.execute($~[:q], 'Query', uri.to_s)
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
        uri = doclink(path, find_anchor(descname))
        insert.execute(func, type, uri.to_s)
      }
    }
  }
end

desc 'Archive the generated docset into a tarball'
task :archive do
  sh 'tar', '-zcf', DOCSET_ARCHIVE, '--exclude=.DS_Store', DOCSET
end

desc 'Delete all fetched files and generated files'
task :clean do
  rm_rf [DOCS_DIR, ICON_FILE, DOCSET, DOCSET_ARCHIVE]
end

task :default => :build
