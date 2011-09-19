#
# Seed for CBRAIN
#

require 'readline'
require 'socket'

#
# ActiveRecord extensions for seeding
#
class ActiveRecord::Base

  def self.seed_record!(attlist, create_attlist = {}, options = {}) # some gems like "seed_fu" already define a "seed" method
    raise "Bad attribute list." if attlist.blank? || ! attlist.is_a?(Hash)

    top_superclass = self
    while top_superclass.superclass < ActiveRecord::Base
      top_superclass = top_superclass.superclass
    end

    exists = top_superclass.where(attlist).all

    # None exists? Create one.
    if exists.empty?
      new_record = self.new()
      attlist.merge(create_attlist).each do |att,val|
        new_record.send("#{att}=",val)
      end
      yield(new_record) if block_given?
      new_record.save!
      puts "#{new_record.class} '#{new_record.send(options[:info_name_method])}' : created." if options[:info_name_method]
      return new_record
    end

    # One exists? Check it.
    if exists.size == 1
      exist = exists[0]
      raise "Tried to seed a record of class #{self.name} but found one of class #{exist.class.name} !" unless exist.is_a?(self)
      create_attlist.each do |att,val|
        exist.send("#{att}=",val)
      end
      # Check other properties here?
      yield(exist) if block_given?
      exist.save!
      puts "#{exist.class} '#{exist.send(options[:info_name_method])}' : updated." if options[:info_name_method]
      return exist
    end

    # More than one exists? Die.
    raise "Several (#{exists.size}) #{top_superclass.name} objects already exists with these attributes."
  end

end

#------------------------------------------------
# Seeding steps starts here
#------------------------------------------------

raise "The seeding process must be run by a process connected to a terminal" unless
  STDIN.tty? && STDOUT.tty? && STDERR.tty?
stty_save = `stty -g`.chomp
trap('INT') { system('stty', stty_save) ; puts "\n\nInterrupt. Exiting."; exit(0) }
hostname = Socket.gethostname

print <<INTRO

===========================================================
CBRAIN seeding process.

This code will install the minimum amount of information
in CBRAIN to get a working system.

You can run it multiple times without fear.
===========================================================

INTRO



puts <<STEP
----------------------------
Step 1: Portal Instance Name
----------------------------

STEP

portal_name = nil
portal_name_file = "#{Rails.root}/config/initializers/config_portal.rb"
if ENV['CBRAIN_RAILS_APP_NAME'] # env variable has priority
  puts "Found environment variable 'CBRAIN_RAILS_APP_NAME'..."
  portal_name = ENV['CBRAIN_RAILS_APP_NAME']
elsif File.exists?(portal_name_file)
  puts "Found config file '#{portal_name_file}', loading it..."
  require portal_name_file rescue nil
  portal_name = CBRAIN::CBRAIN_RAILS_APP_NAME if CBRAIN.const_defined?('CBRAIN_RAILS_APP_NAME')
  unless portal_name
    puts "It seems the file exists but doesn't define the CBRAIN_RAILS_APP_NAME ?"
    puts "This seems too weird to continue, so please investigate first. Quitting."
    Kernel.exit(10)
  end
end

if ! portal_name.blank?
  raise "Invalid name for the portal." if portal_name !~ /^[a-z]\w+$/i
  puts "Portal name: #{portal_name}"
  puts ""
end

# Interactive question
if portal_name.blank?
  puts "Enter a name (a simple identifier) for the Portal."
  puts ""
  print "Portal name: "
  portal_name = Readline.readline
  raise "Invalid name for the portal." if portal_name.blank? || portal_name !~ /^[a-z]\w+$/i
  puts ""
end



puts <<-STEP
----------------------------
Step 2: Admin User Password
----------------------------

Enter a password for the admin user. If the admin user
already exists, this will reset it. Leave blank to leave
the existing password unchanged.

STEP
print "Admin's password: "
system("stty","-echo")
passwd = STDIN.readline.chomp # Readline.readline
system("stty","echo")
puts "\n"

print "Confirm admin password: "
system("stty","-echo")
passwd2 = STDIN.readline.chomp # Readline.readline
system("stty","echo")
puts "\n"

if passwd != passwd2
  puts "Password mismatch. Quitting."
  Kernel.exit(20)
end

puts ""



puts <<-STEP
----------------------------
Step 3: Seeding The Database
----------------------------

STEP

# Create the 'everyone' group.
everyone = SystemGroup.seed_record!(
  {
     :name  => "everyone"
  },
  {},
  { :info_name_method => :name }
)

# Create admin user.
admin = User.seed_record!(
  {
    :login     => 'admin',
    :role      => 'admin'
  },
  {
    :full_name             => "CBRAIN Administrator",
    :email                 => "nobody@#{hostname}"
  },
  { :info_name_method => :login }
) do |u|
  unless passwd.blank?
    u.password              = passwd
    u.password_confirmation = passwd
  end
end

# Update creator ID for the two system groups
admin.own_group.update_attributes!(:creator_id => admin.id)
everyone.update_attributes!(:creator_id => admin.id)

# Create portal object
portal = BrainPortal.seed_record!(
  {
    :user_id          => admin.id,
    :group_id         => everyone.id,
    :ssh_control_host => hostname
  },
  {
    :name        => portal_name,
    :online      => true,
    :read_only   => false,
    :description => "CBRAIN BrainPortal on host #{hostname}"
  },
  { :info_name_method => :name }
)

puts ""



puts <<-STEP
----------------------------
Step 4: Portal config file
----------------------------

STEP
if ENV['CBRAIN_RAILS_APP_NAME']
  puts "Not touching the config file, since we got our portal name from CBRAIN_RAILS_APP_NAME."
else
  puts "(Re)creating the config file with the name of this portal..."

  template = File.read("#{portal_name_file}.TEMPLATE")
  template.sub!(/^\s*CBRAIN_RAILS_APP_NAME\s*=[^\n]*/m, "  CBRAIN_RAILS_APP_NAME = \"#{portal_name}\"")
  File.open(portal_name_file, "w") do |fh|
    fh.write(template)
  end
end

puts ""



puts <<-STEP
----------------------------
Step 5: ALL DONE !
----------------------------

Exiting.
STEP

