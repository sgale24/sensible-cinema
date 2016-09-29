require "./kemal_server/*"

# module KemalServer
  # TODO Put your code here
# end

require "kemal"

get "/" do
  "Hello World! Clean stream it! <a href=/index>index</a>"
end

def setup(env)
  env.set "url_unescaped", unescaped = env.params.query["url"] # already unescaped it on its way in...
  env.set "url_escaped", url_escaped = URI.escape(unescaped)
  env.set "path" , "edit_descriptors/#{url_escaped}" 
end

before_get "/for_current" do |env|
  setup(env)
end

before_get "/edit" do |env|
  setup(env)
end
before_post "/save" do |env|
  setup(env)
end

get "/for_current" do |env|
  path = env.get("path").as(String)
  if (!File.exists?(path) || path.includes?(".."))
    env.response.status_code = 403
    # never did figure out how to write this to the output :|
    "unable to find one yet for #{env.get("url_unescaped")} <a href=\"/edit?url=#{env.get("url_escaped")}\">create new</a>" # too afraid to do straight redirect :)
  else
    mutes_and_skips = File.read path
    env.response.content_type = "application/javascript"
    render "src/views/html5_edited.js.ecr"
  end
end

get "/edit" do |env|
  path = env.get("path").as(String)
  if File.exists?(path)
    current_text = File.read(path)
  else
    current_text = "// template [remove this line]:
var name=\"movie name\";
var mutes=[[2.0,7.0]]; 
var skips=[[10.0, 30.0]]"
  end
  
  render "src/views/edit.ecr"
end

get "/index" do
  urls_names = Dir["edit_descriptors/*"].map{|fullish_name| 
    url = URI.unescape File.basename(fullish_name) 
    File.read(fullish_name) =~ /name="(.+)"/
    name = $1
    [url, name]
  }
  render "src/views/index.ecr"
end

post "/save" do |env|
  path = env.get("path").as(String)
  got = env.params.body["stuff"]
  log("attempt save  #{path} as #{got}")
  if got.lines.size != 3
    raise "got non 3 lines?"
  end
  got = got.gsub("\r\n", "\n")
  name = got.lines[0]
  mutes = got.lines[1]
  skips = got.lines[2]
  if name !~ /(var name="[^"]+";)/
    raise "bad name? use browser back arrow"
  end
  if mutes !~ /var mutes=[\[\]\d\., ]+;/
    raise "bad mutes? use browser back arrow"
  end
  if skips !~ /var skips=[\[\]\d\., ]+;/
    raise "bad skips? use browser back arrow"
  end
  # TODO more security :| or just allow input like a normal site rather LOL
  #if got !~ /^var name="[^"]+";\nvar mutes=[\[\]\d\., ]+;\nvar mutes=[\[\]\d\., ]+;$/m # ??
  desired_size = (name.size + mutes.size + skips.size) # wait they include \n ???
  if got.size != desired_size
    #raise "extra stuff? use browser back #{got} #{desired_size} != #{got.size} #{got.inspect}"
  end
  File.write(path, got);
  "saved it #{env.get("url_unescaped")}<br>#{got.size}<a href=/index>index</a><br/><a href=/edit?url=#{env.get "url_escaped"}>re-edit</a>"
end

Kemal.run