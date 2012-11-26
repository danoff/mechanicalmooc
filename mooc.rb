require 'sinatra'
require 'dm-core'
require 'dm-timestamps'
require 'dm-validations'
require 'dm-migrations'
require 'rest_client'

DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/development.db")

class User
  include DataMapper::Resource

  belongs_to :group, :required => false

  property :id, Serial
  property :email, String, :required => true
  property :group_work, Boolean, :default => true
  property :learning_style, String
  property :expertise, String
  property :timezone, String
  property :image, String
  property :unsubscribed, Boolean, :default => false
  property :round, Integer, :default => 1

  property :unsubscribed_at, DateTime
  property :created_at, DateTime
  property :updated_at, DateTime

  validates_uniqueness_of :email
  validates_format_of :email, :as => :email_address
  
  after :create do
    send_welcome_email
    add_user_to_all_list
  end
  
  def send_welcome_email
    body_html = File.read('emails/signup-confirmation.html')
    body_text = File.read('emails/signup-confirmation.txt')
    subject = "Thanks for signing up"
    RestClient.post "https://api:#{ENV['MAILGUN_API_KEY']}"\
    "@api.mailgun.net/v2/mechanicalmooc.org/messages",
    :from => "The Machine <the-machine@mechanicalmooc.org>",
    :to => email,
    :subject => subject,
    :text => body_text,
    :html => body_html
  end

  def add_user_to_all_list
    RestClient.post("https://api:#{ENV['MAILGUN_API_KEY']}" \
                    "@api.mailgun.net/v2/lists/python-all@mechanicalmooc.org/members",
                    :address => email,
                    :upsert => 'yes')
  end

end

class Group
  include DataMapper::Resource

  has n, :users

  property :id, Serial
  property :timezone, String

  property :created_at, DateTime
  property :updated_at, DateTime
  
  after :create, :start_list
  after :save, :upsert_list_members
  after :update, :upsert_list_members
  after :destroy, :delete_list

  def start_list
    RestClient.post("https://api:#{ENV['MAILGUN_API_KEY']}" \
                      "@api.mailgun.net/v2/lists",
                      :address => list_address,
                      :access_level => 'members',
                      :description => timezone)
    RestClient.post("https://api:#{ENV['MAILGUN_API_KEY']}" \
                    "@api.mailgun.net/v2/lists/#{list_address}/members",
                    :address => "the-machine@mechanicalmooc.org",
                    :upsert => 'yes')
  end
  
  def upsert_list_members
    # puts "Adding members"
    users.each do |u|
      RestClient.post("https://api:#{ENV['MAILGUN_API_KEY']}" \
                      "@api.mailgun.net/v2/lists/#{list_address}/members",
                      :address => u.email,
                      :upsert => 'yes')
    end
  end

  def delete_list
    RestClient.delete("https://api:#{ENV['MAILGUN_API_KEY']}" \
                      "@api.mailgun.net/v2/lists/#{list_address}")
  end
  
  def list_address
    "python-#{id}@mechanicalmooc.org"
  end
end

class MoocLog
  include DataMapper::Resource

  property :id, Serial
  property :created_at, DateTime
  
  property :event, String
  property :recipient, String
  property :domain, String
  property :message_headers, String
  property :message_id, String
  property :timestamp, String
  property :extra, String

end


DataMapper.finalize
DataMapper.auto_upgrade!

# Begin Web server portion
################################################################################

get '/' do
  File.read(File.join('public', 'index.html'))
end

post '/signup' do
  User.create(
    :email => params[:email],
    :group_work => params[:groupRadios],
    :learning_style => params[:styleRadios],
    :expertise => params[:expertiseRadios],
    :timezone => params[:timezone],
    :round => 2
  )
  "Thanks for signing up, we'll email you soon."
end

post '/mooc-mailgun-log' do
  group_from_header_regex = /python-[0-9]{1,4}@mechanicalmooc.org/
  s = MoocLog.create(
                 :event => params.delete("event").to_s,
                 :recipient => params.delete("recipient").to_s,
                 :domain => params.delete("domain").to_s,
                 :message_headers => params.delete("message-headers").to_s[group_from_header_regex],
                 :message_id => params.delete("Message-Id").to_s,
                 :timestamp => params.delete("timestamp").to_s)
                 # :extra => params.to_s[0..50])
  "400 OK"
end


# admin uris
###########################################################################################

# Http auth stuff 
# Set the admin user and pass in heroku config

helpers do
  def protected!
    unless authorized?
      response['WWW-Authenticate'] = %(Basic realm="Restricted Area")
      throw(:halt, [401, "Not authorized\n"])
    end
  end

  def authorized?
    @auth ||=  Rack::Auth::Basic::Request.new(request.env)
    @auth.provided? && @auth.basic? && @auth.credentials && @auth.credentials == [ENV['ADMIN_USER'], ENV['ADMIN_PASS']]
  end
end

get '/admin' do
  protected!
  File.read(File.join('public', 'admin.html'))
end

post '/admin/send-email' do
  protected!
  puts "REAL"
  puts params[:sequence]
  puts params[:subject]
  puts params[:tags]
  puts params[:body_text]
  # RestClient.post("https://api:#{ENV['MAILGUN_API_KEY']}"\
  #                 "@api.mailgun.net/v2/mechanicalmooc.org/messages",
  #                 :from => "The Machine <the-machine@mechanicalmooc.org>",
  #                 :to => email,
  #                 :subject => "Hello",
  #                 :text => "Thanks for signing up")
end

post '/admin/send-test-email' do
  protected!
  puts "TEST"
  puts params[:sequence]
  puts params[:subject]
  puts params[:tags]
  puts params[:body_text]
  html_body = "<html><body>THIS IS A TEST EMAIL!!! <hr />"
  html_body += params[:body_text] + "</body></html>"
  puts html_body
  RestClient.post("https://api:#{ENV['MAILGUN_API_KEY']}"\
                  "@api.mailgun.net/v2/mechanicalmooc.org/messages",
                  :from => "The Machine <the-machine@mechanicalmooc.org>",
                  :to => params[:test_email],
                  :subject => params[:subject],
                  :html => html_body)
end

