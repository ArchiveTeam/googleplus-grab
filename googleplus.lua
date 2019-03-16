dofile("table_show.lua")
dofile("urlcode.lua")
JSON = (loadfile "JSON.lua")()

local item_type = os.getenv('item_type')
local item_value = os.getenv('item_value')
local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

local users = {}
local queueing_posts = false
local error_count = {}

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

load_json_file = function(file)
  if file then
    return JSON:decode(file)
  else
    return nil
  end
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

allowed = function(url, parenturl)
  if string.match(url, "'+")
      or string.match(url, "[<>\\%*%$;%^%[%],%(%){}]")
      or string.match(url, "^https?://plus%.google%.com/up/")
      or string.match(url, "^https?://accounts%.google%.com/")
      or string.match(url, "/_/PlusAppUi/manifest%.json$")
      or string.match(url, "^https?://[^/]*gstatic%.com/")
      or string.match(url, "^https?://[^/]*googleusercontent%.com/proxy/") then
    return false
  end

  if queueing_posts == false and string.match(url, "^https?://plus%.google%.com/[^/]+/posts/.+") then
    queueing_posts = true
  end

  if item_type ~= "userfull" and string.match(url, "^https?://plus%.google%.com/photos/") then
    return false
  end

  local tested = {}
  for s in string.gmatch(url, "([^/]+)") do
    if tested[s] == nil then
      tested[s] = 0
    end
    if tested[s] == 6 then
      return false
    end
    tested[s] = tested[s] + 1
  end

  if string.match(url, "^https?://[^/]*googleusercontent%.com/") then
    if string.match(url, "^https?://[^/]+/[^/]+/[^/]+/[^/]+/[^/]+/w[0-9]+[^/]+/[^/]+$")
        or (queueing_posts and string.match(url, "^https?://[^/]+/[^=]+=w[0-9]+"))
        or (not queueing_posts and string.match(url, "^https?://[^/]+/proxy/[^=]+=w[0-9]+")) then
      if string.match(url, "[=/]w530[^0-9]") then
        return true
      end
      return false
    end
    return not queueing_posts
  end

  if string.match(url, "^https?://plus%.google%.com/_/PlusAppUi/.+_reqid=") then
    return true
  end

  for s in string.gmatch(url, "([^/]+)") do
    if users[s] then
      return true
    end
  end
  
  return false
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]

  if string.match(url, "[<>\\%*%$;%^%[%],%(%){}]")
      or string.match(url, "^https?://[^/]*gstatic%.com/") then
    return false
  end

  if string.match(url, "^https?://[^/]*googleusercontent%.com/") then
    if not allowed(url, parent["url"]) then
      return false
    end
  end

  if (downloaded[url] ~= true and addedtolist[url] ~= true)
      and (allowed(url, parent["url"]) or html == 0) then
    addedtolist[url] = true
    return true
  end
  
  return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil
  
  downloaded[url] = true

  local function check(urla)
    local origurl = url
    local url = string.match(urla, "^([^#]+)")
    local url_ = string.gsub(url, "&amp;", "&")
    local url_ = string.gsub(url_, "\\u0026", "&")
    local url_ = string.gsub(url_, "\\u003[dD]", "=")
    if item_type == "userfull" and string.match(url, "^https?://plus%.google%.com/photos/[0-9]+/albums/[0-9]+/[0-9]+$") then
      local id1, id2 = string.match(url, "^https?://[^/]+/[^/]+/([0-9]+)/[^/]+/[0-9]+/([0-9]+)$")
      check("https://plus.google.com/photos/photo/" .. id1 .. "/" .. id2)
    end
    if string.match(url_, "w256%-h86") and downloaded[url_] ~= true and addedtolist[url_] ~= true then
      table.insert(urls, { url=url_ })
      table.insert(urls, { url=string.gsub(url_, "w256%-h86", "w1084-h610") })
    end
    if (downloaded[url_] ~= true and addedtolist[url_] ~= true)
        and allowed(url_, origurl) then
      table.insert(urls, { url=url_ })
      addedtolist[url_] = true
      addedtolist[url] = true
    end
  end

  local function checknewurl(newurl)
    if string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"))
    elseif string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^\\/\\/") then
      check(string.match(url, "^(https?:)") .. string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^//") then
      check(string.match(url, "^(https?:)") .. newurl)
    elseif string.match(newurl, "^\\/") then
      check(string.match(url, "^(https?://[^/]+)") .. string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^/") then
      check(string.match(url, "^(https?://[^/]+)") .. newurl)
    elseif string.match(newurl, "^%./") then
      checknewurl(string.match(newurl, "^%.(.+)"))
    end
  end

  local function checknewshorturl(newurl)
    if string.match(newurl, "^%?") then
      check(string.match(url, "^(https?://[^%?]+)") .. newurl)
    elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
       or string.match(newurl, "^[/\\]")
       or string.match(newurl, "^%./")
       or string.match(newurl, "^[jJ]ava[sS]cript:")
       or string.match(newurl, "^[mM]ail[tT]o:")
       or string.match(newurl, "^vine:")
       or string.match(newurl, "^android%-app:")
       or string.match(newurl, "^ios%-app:")
       or string.match(newurl, "^%${")) then
      check(string.match(url, "^(https?://.+/)") .. newurl)
    end
  end

  if string.match(url, "^https?://plus%.google%.com/[0-9]+$") then
    users[string.match(url, "^https?://[^/]+/([0-9]+)$")] = true
  end

  if allowed(url, nil) and not string.match(url, "^https?://[^/]*googleusercontent%.com/") then
    html = read_file(file)
    if string.match(url, "^https?://plus%.google%.com/[0-9]+$") then
      if string.match(html, '<link%s+rel="canonical"%s+href="https?://plus%.google%.com/[^/"]+">') then
        local canonical = string.match(html, '<link%s+rel="canonical"%s+href="https?://plus%.google%.com/([^/"]+)">')
        users[canonical] = true
        if string.match(html, '<span%s+class="RveJvd%s+snByac">View%s+all</span>') then
          check(url .. "/palette")
          check("https://plus.google.com/" .. canonical .. "/palette")
        end
      elseif string.match(html, '<span%s+class="RveJvd%s+snByac">View%s+all</span>') then
        check(url .. "/palette")
      end
      local sid = string.match(html, '"FdrFJe":"([^"]+)"')
      local version = string.match(html, '"cfb2h":"([^"]+)"')
      local user_id = string.match(url, "^https?://[^/]+/([0-9]+)$")
      local current_time = os.date("*t")
      local reqid = current_time.hour * 3600 + current_time.min * 60 + current_time.sec
      local data = string.match(html, "AF_initDataCallback%({key:%s+'ds:6'.-return%s*(.-)}}%);</script>")
      if data == nil or sid == nil or version == nil then
        if status_code == 404 then
          return urls
        end
        print('Could not extract data...')
        abortgrab = true
        return urls
      end
      local data = load_json_file(data)
      if data[1][2] ~= nil then
        local newurl = "https://plus.google.com/_/PlusAppUi/data?ds.extension=74333095&f.sid=" .. sid .. "&bl=" .. version .. "&hl=en-US&soc-app=199&soc-platform=1&soc-device=1&_reqid=" .. reqid .. "&rt=c"
        local post_data = 'f.req=[[[74333095,[{"74333095":["' .. data[1][2] .. '","' .. user_id .. '"]}],null,null,0]]]'
        table.insert(urls, {url=newurl, post_data=post_data})
      end
    end
    if string.match(url, "^https?://plus%.google%.com/_/PlusAppUi/.+_reqid=") then
      local reqid = string.match(url, "_reqid=([0-9]+)")
      if tonumber(reqid) < 100000 then
        reqid = reqid + 100000
      end
      reqid = reqid + 100000
      local newurl = string.gsub(url, "_reqid=[0-9]+", "_reqid=" .. reqid)
      local data = load_json_file(string.match(html, "^%)%]}'%s+[0-9]+(.+)"))
      for _, d in pairs(data[1][3]['74333095'][1][8]) do
        check("https://plus.google.com/" .. d[7]["33558957"][22])
      end
      if data[1][3]['74333095'][1][2] ~= nil then
        local post_data = 'f.req=[[[74333095,[{"74333095":["' .. data[1][3]['74333095'][1][2] .. '","' .. data[1][3]['74333095'][1][8][1][7]['33558957'][17] .. '"]}],null,null,0]]]'
        table.insert(urls, {url=newurl, post_data=post_data})
      end
      return urls
    end
    if string.match(url, "^https?://plus%.google%.com/[^/]+/posts/.+") then
      html = string.gsub(html, '<meta%s+property="og:image"%s+content="https?://[^/]*googleusercontent%.com/[^"]+">', '')
    end
    for newurl in string.gmatch(string.gsub(html, "&quot;", '"'), '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(string.gsub(html, "&#039;", "'"), "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, ":%s*url%(([^%)]+)%)") do
      checknewurl(newurl)
    end
  end

  return urls
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]
  
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. "  \n")
  io.stdout:flush()

  if (status_code >= 300 and status_code <= 399) then
    local newloc = string.match(http_stat["newloc"], "^([^#]+)")
    if string.match(newloc, "^//") then
      newloc = string.match(url["url"], "^(https?:)") .. string.match(newloc, "^//(.+)")
    elseif string.match(newloc, "^/") then
      newloc = string.match(url["url"], "^(https?://[^/]+)") .. newloc
    elseif not string.match(newloc, "^https?://") then
      newloc = string.match(url["url"], "^(https?://.+/)") .. newloc
    end
    if downloaded[newloc] == true or addedtolist[newloc] == true then
      return wget.actions.EXIT
    end
  end
  
  if (status_code >= 200 and status_code <= 399) then
    downloaded[url["url"]] = true
    downloaded[string.gsub(url["url"], "https?://", "http://")] = true
  end

  if abortgrab == true then
    io.stdout:write("ABORTING...\n")
    return wget.actions.ABORT
  end

  if string.match(url["url"], "/browser%-not%-supported/") then
    return wget.actions.ABORT
  end

  local domain = string.match(url["url"], "^https?://([^/]+)")
  
  if status_code >= 500
      or (status_code >= 400 and status_code ~= 403 and status_code ~= 404)
      or status_code  == 0 then
    io.stdout:write("Server returned " .. http_stat.statcode .. " (" .. err .. "). Sleeping.\n")
    io.stdout:flush()
    local maxtries = 8
    if not allowed(url["url"], nil) then
      maxtries = 2
    end
    if tries > maxtries then
      if status_code == 400 then
        if error_count[domain] == 9 then
          return wget.actions.ABORT
        end
        if error_count[domain] == nil then
          error_count[domain] = 0
        end
        error_count[domain] = error_count[domain] + 1
        return wget.actions.EXIT
      end
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      if allowed(url["url"], nil) then
        return wget.actions.ABORT
      else
        return wget.actions.EXIT
      end
    else
      os.execute("sleep " .. math.floor(math.pow(2, tries)))
      tries = tries + 1
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  if error_count[domain] ~= nil and error_count[domain] > 0 then
    error_count[domain] = error_count[domain] - 1
  end

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab == true then
    os.execute("live-stats.sh 'ABORT'")
    return wget.exits.IO_FAIL
  end
  return exit_status
end
