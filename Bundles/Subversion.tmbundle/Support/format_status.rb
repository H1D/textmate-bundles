
# Includes
support = ENV['TM_SUPPORT_PATH']
require (support + "/bin/Builder.rb")
require (support + "/bin/shelltokenize.rb")
require (support + "/lib/escape.rb")
require "cgi"

# Arguments
bundle				= ENV['TM_BUNDLE_SUPPORT']
work_path			= ENV['WorkPath']
work_paths			= TextMate.selected_paths_array
ignore_file_pattern = /(\/.*)*(\/\..*|\.(tmproj|o|pyc)|Icon)/

# First escape for use in the shell, then escape for use in a JS string
def e_sh_js(str)
  (e_sh str).gsub("\\", "\\\\\\\\")
end

def shorten_path(path)
	prefix = ENV['WorkPath']
	if prefix.nil?
		work_paths = TextMate.selected_paths_array
		prefix = work_paths.first unless work_paths.nil? || work_paths.size != 1
	end

	if prefix && prefix == path
		File.basename(path)
	elsif prefix
		File.expand_path(path).gsub(/#{Regexp.escape prefix}\//, '')
	else
		File.expand_path(path).gsub(/#{Regexp.escape File.expand_path('~')}/, '~')
	end
end

svn = ENV['TM_SVN'] || 'svn'
svn = `which svn`.chomp unless svn[0] == ?/

work_path = work_paths[0] if work_path.nil? and (not work_paths.nil?) and (work_paths.size == 1)
work_path ||= '(selected files)'

#
# Status or update?
#
$is_status = false

ARGV.each {|arg| $is_status = true if arg == "--status"}

command_name = if $is_status then
	"status"
else
	"update"
end

mup = Builder::XmlMarkup.new(:target => STDOUT)

class << mup
	
	StatusColumnNames = ['File', 'Property', 'Lock', 'History', 'Switched', 'Repository Lock']
	
	StatusMap = {	'A' => 'added',
					'D' => 'deleted',
					'G' => 'merged',
					'U' => 'updated',
					'M' => 'modified',
					'L' => 'locked',
					'B' => 'broken',
					'R' => 'replaced',
					'C' => 'conflict',
					'!' => 'missing',
					'+' => 'added',
					'"' => 'typeconflict',
					'?' => 'unknown',
					'I' => 'ignored',
					'X' => 'external',
					' ' => 'none'}
	
	# this may be more dynamic in the future
	# it also possibly should not be stashed in mup
	def status_column_count
		# update has three columns vs. up to eight for status as of 1.3.x
		# But, for status, if we assume eight, we might have compatibility
		# issues with earlier versions which had fewer columns (unless they
		# had more padding than I recall). The last three columns seem to be
		# network status-only, so this isn't a big deal for now.
		$is_status ? 5 : 3
	end
	
	def status_map(status)
		StatusMap[status]
	end
	
	def td_status!(status,id)
		status_column_count.times do |i|
			
			c = status[i].chr
			status_class = StatusMap[c] || 'dunno'
			td(c, "class" => status_class, "title" => StatusColumnNames[i] + " " + status_class.capitalize, :id => "status#{id}")
		end
	end
end

mup.html {
	mup.head {
			mup.title("Subversion #{command_name.capitalize}")
			mup.style( "@import 'file://"+bundle+"/Stylesheets/svn_status_style.css';", "type" => "text/css")
			mup << (%{<script>
					// the filename passed in to the following functions is already properly shell escaped
					diff_to_mate = function(filename,id){
						TextMate.isBusy = true;
						tmp = '/tmp/diff_to_mate' + id + '.diff'
						cmd = '#{e_sh svn} 2>&1 diff ' + filename + ' >' + tmp + ' && open -a TextMate ' + tmp
						document.getElementById('STATUS').innerHTML = TextMate.system(cmd, null).outputString
						TextMate.isBusy = false;
					};
					svn_add = function(filename,id){
						TextMate.isBusy = true;
						cmd = '#{e_sh svn} 2>&1 add ' + filename
						document.getElementById('STATUS').innerHTML = TextMate.system(cmd, null).outputString
						document.getElementById('status'+id).innerHTML = 'A';
						document.getElementById('status'+id).className = '#{mup.status_map('A')}';
						TextMate.isBusy = false;
					};
					svn_revert = function(filename,id){
						TextMate.isBusy = true;
						cmd = '#{e_sh svn} 2>&1 revert ' + filename;
						document.getElementById('STATUS').innerHTML = TextMate.system(cmd, null).outputString;
						document.getElementById('status'+id).innerHTML = '?';
						document.getElementById('status'+id).className = '#{mup.status_map('?')}';
						TextMate.isBusy = false;
					};
					svn_remove = function(filename,id,displayname){
						cmd = '#{e_sh_js ENV['TM_BUNDLE_SUPPORT']}/remove_file.rb -svn=#{e_sh_js svn} -path=' + filename + ' -displayname=' + displayname;
						myCommand = TextMate.system(cmd, function (task) { });
						myCommand.onreadoutput = svn_remove_output;
					}
					svn_remove_output = function(str){
						document.getElementById('STATUS').innerHTML = str;
					}
					finder_open = function(filename,id){
						TextMate.isBusy = true;
						cmd = "open 2>&1 " + filename
						document.getElementById('STATUS').innerHTML = TextMate.system(cmd, null).outputString
						TextMate.isBusy = false;
					};
				</script>}
			)
	}

	mup.body {
		mup.h1 do 
			mup.img(	:src => "file://"+bundle+"/Stylesheets/subversion_logo.tiff",
						:height => 21,
						:width => 32 )
			mup.text " #{command_name.capitalize} for "
			mup << "&ldquo;"
			mup.text "#{File.basename(work_path)}"
			mup << "&rdquo;"
		end
#		mup.hr
#		mup.div("class" => "command"){ mup.strong("#{svn} #{command_name}"); mup.text!(" " + work_path) } #mup.text!("checking "); 
		STDOUT.flush
		
		mup.div( "class" => "section" ) do
			mup.table("class" => "status") {
			
				match_columns		= '.' * mup.status_column_count
				unknown_file_status	= '?' + (' ' * (mup.status_column_count - 1))
				missing_file_status	= '!' + (' ' * (mup.status_column_count - 1))
				added_file_status	= 'A' + (' ' * (mup.status_column_count - 1))
			
				stdin_line_count = 1
				STDIN.each_line do |line|
				
					# ignore lines consisting only of whitespace
					next if line.squeeze.strip.empty?
					# build the row
					mup.tr {
						if /^svn:/.match( line ).nil? then
							match = /^(#{match_columns})(?:\s+)(.*)\n/.match( line )
							if match.nil? then
								mup.td(:colspan => (mup.status_column_count + 4).to_s ) do
									mup.div(:class => 'info') { mup.text(line) }
								end
							else
								status	= match[1]
								file	= match[2]
								esc_file = '&quot;' + CGI.escapeHTML(e_sh_js(file).gsub(/(?=")/, '\\')) + '&quot;'

								if status == unknown_file_status and ignore_file_pattern =~ file
									# This is a file that we don't want to know about
									nil
								else
									mup.td_status!(status, stdin_line_count)

									# ADD Column 
									mup.td(:class => 'add_col') {
										if status == unknown_file_status
											mup.a( 'Add', "href" => '#', "class" => "add button", "onclick" => "svn_add(#{esc_file},#{stdin_line_count}); return false" )
										else
											mup << ' '
										end
									}

									# REVERT Column 
									mup.td(:class => 'revert_col') {
										if status != unknown_file_status
											mup.a( 'Revert', "href" => '#', "class" => "revert button", "onclick" => "svn_revert#{"_confirm" unless status == added_file_status}(#{esc_file},#{stdin_line_count}); return false" )
										else
											mup << ' '
										end
									}

									# REMOVE Column 
									mup.td(:class => 'remove_col') {
										if status == missing_file_status
											mup.a( 'Remove', "href" => '#', "class" => "remove button", "onclick" => "svn_remove(#{esc_file},#{stdin_line_count},'#{CGI.escapeHTML(shorten_path(file))}'); return false" )
										else
											mup << ' '
										end
									}

									if file.match(/\.(png|gif|jpe?g|psd|tiff|zip|rar)$/i)
										onclick        = "finder_open(#{esc_file},#{stdin_line_count}); return false"
										filename_title = 'Open in the Finder'
										column_is_an_image = true
									else
										onclick        = ""
										filename_title = 'Open in TextMate'
										# Diff Column (only available for text)
										column_is_an_image = false
									end
									if column_is_an_image or status == unknown_file_status
										mup.td(:class => 'diff_col') { mup << ' ' }
									else
										mup.td(:class => 'diff_col') { mup.a( 'Diff', "href" => '#', "class" => "diff button", "onclick" => "diff_to_mate(#{esc_file},#{stdin_line_count}); return false" ) } unless status == unknown_file_status
									end

									mup.td(:class => 'file_col') {
										mup.a( shorten_path(file), "href" => 'txmt://open?url=file://' + (e_url file), "class" => "pathname", "onclick" => onclick, :title => "#{CGI.escapeHTML(filename_title)}\n\n#{CGI.escapeHTML(file)}" )
									}
								end
							end 
						else
							mup.td { mup.div( line, "class" => "error" ) }
						end
					}
					stdin_line_count = stdin_line_count + 1
				end
			}
		end
		mup.br(:style => 'clear:both')
		mup.div(:id => 'STATUS'){mup << " "}
	}
}
