require 'json'
require 'net/http'
require 'time'
require 'base64'
require 'uri'
require 'open-uri'

ENV["SSL_CERT_FILE"] = "./cacert.pem"
IMPORTED = './imported.json'

credentials = open('./credentials.json') do |io|
  JSON.load(io)
end

imported_articles = open(IMPORTED) do |io|
  JSON.load(io)
end

UPDATED = './url_updated.json'

url_updated_articles = open(UPDATED) do |io|    
    JSON.load(io)  
end

COOKIE_STR = credentials['COOKIE_STR']
ACCESS_TOKEN = credentials['ACCESS_TOKEN']
TEAM_DOMAIN = credentials['TEAM_DOMAIN']
GROUP_ID = credentials['GROUP_ID']
USER_IDS = credentials['USER_IDS']
USER_ETC = credentials['USER_ETC']
QIITA_TEAM = credentials['QIITA_TEAM']

BASE_URL       = URI.parse('https://api.docbase.io')
REQUEST_HEADER = {'X-DocBaseToken' => ACCESS_TOKEN, 'X-Api-Version' => 1, 'Content-Type' => 'application/json'}

def wait
  # 1時間に300回を超えるリクエストは無効のため待つ
  start_at = Time.now
  yield
  sleep_sec = [3600 / 300.0 - (Time.now - start_at), 0].max
  sleep(sleep_sec)
end

qiita_articles = {}

imported_articles.each do |key, value|
    qiita_articles[value['qiita']] = value['docbase']
end

def getArticle(request_path)
    http = Net::HTTP.new(BASE_URL.host, BASE_URL.port)
    http.use_ssl = BASE_URL.scheme == 'https'
  
    request = Net::HTTP::Get.new(request_path)
    REQUEST_HEADER.each { |key, value| request.add_field(key, value) }
  
    response = http.request(request)
    response_body = JSON.parse(response.body)
  
    if response.code == '200'
      response_body
    else
      message = response_body['messages'].join("\n")
      puts "Error: #{message}"
      nil
    end
end

def updateArticle(request_path, data)   
    http = Net::HTTP.new(BASE_URL.host, BASE_URL.port)
    http.use_ssl = BASE_URL.scheme == 'https'
  
    request = Net::HTTP::Patch.new(request_path)
    request.body = data
    REQUEST_HEADER.each { |key, value| request.add_field(key, value) }
  
    response = http.request(request)
    response_body = JSON.parse(response.body)
  
    if response.code == '200'
      response_body
    else
      message = response_body['messages'].join("\n")
      puts "Error: #{message}"
      nil
    end
end

qiita_articles.each do |qiita_url, docbase_url|
    if url_updated_articles.has_key?(docbase_url) then
        puts "Article: #{docbase_url} is skipped."
        next
    end

    article_id = docbase_url.split("/").last
    body = nil

    puts "Updating https://strobo.docbase.io/posts/#{article_id}"

    wait do
        rjson = getArticle("/teams/#{TEAM_DOMAIN}/posts/#{article_id}")
        body = rjson['body']
        
        body = body.gsub(/https?:\/\/#{QIITA_TEAM}.qiita.com\/([0-9a-z\-.]+)\/items\/([0-9a-z\-.]+)/) do | qiita_article_url|
            docbase_new_url = qiita_articles[qiita_article_url]
            puts "\tUpdate: #{qiita_article_url}"
            docbase_new_url
        end        
    end

    wait do
      update_json = {
          body: body
      }.to_json
      updateArticle("/teams/#{TEAM_DOMAIN}/posts/#{article_id}", update_json)  
    end

    puts "\tSuccess: https://strobo.docbase.io/posts/#{article_id}"

    url_updated_articles[docbase_url] = {}
    open(UPDATED, 'w') do |io| 
        JSON.dump(url_updated_articles, io)
    end
end
