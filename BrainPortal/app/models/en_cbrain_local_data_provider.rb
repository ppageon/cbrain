
#
# CBRAIN Project
#
# $Id$
#

require 'fileutils'

#
# This class provides an implementation for a data provider
# where the remote files are not even remote, they are local
# to the currently running rails application. The provider's
# files are stored in the new 'cbrain enhanced
# directory tree'; such a tree stores the file "hello"
# into a relative path like this:
#
#     /root_dir/01/23/45/hello
#
# where +root_dir+ is the data provider's +remote_dir+ (a local
# directory) and the components "01", "23" and "45" are computed
# based on the userfile's ID.
#
# This data provider does not cache anything! The 'remote' files
# are in fact all local, and accesing the 'cached' files mean
# accessing the real provider's files. All methods are adjusted
# so that their behavior is sensible.
#
# For the list of API methods, see the DataProvider superclass.
#
class EnCbrainLocalDataProvider < LocalDataProvider

  Revision_info="$Id$"

  def cache_prepare(userfile) #:nodoc:
    SyncStatus.ready_to_modify_cache(userfile) do
      threelevels = cache_subdirs_from_id(userfile.id)
      userdir = Pathname.new(remote_dir)
      level1  = userdir                  + threelevels[0]
      level2  = level1                   + threelevels[1]
      level3  = level2                   + threelevels[2]

      Dir.mkdir(userdir) unless File.directory?(userdir)
      Dir.mkdir(level1)  unless File.directory?(level1)
      Dir.mkdir(level2)  unless File.directory?(level2)
      Dir.mkdir(level3)  unless File.directory?(level3)

      true
    end
  end

  # Returns the real path on the DP, since there is no caching here.
  def cache_full_path(userfile) #:nodoc:
    basename  = userfile.name
    threelevels = cache_subdirs_from_id(userfile.id)
    Pathname.new(remote_dir) + threelevels[0] + threelevels[1] + threelevels[2] + basename
  end

  def cache_erase(userfile) #:nodoc:
    SyncStatus.ready_to_modify_cache(userfile,'ProvNewer') do
      true
    end
  end

  def impl_provider_erase(userfile)  #:nodoc:
    fullpath = cache_full_path(userfile) # actually real path on DP
    parent1  = fullpath.parent
    parent2  = parent1.parent
    parent3  = parent2.parent
    begin
      FileUtils.remove_entry(parent1.to_s, true)
      Dir.rmdir(parent2.to_s)
      Dir.rmdir(parent3.to_s)
    rescue Errno::ENOENT, Errno::ENOTEMPTY => ex
      # It's OK if any of the rmdir fails, and we simply ignore that.
    end
    true
  end

  def impl_provider_rename(userfile,newname)  #:nodoc:
    oldpath   = cache_full_path(userfile)
    oldparent = oldpath.parent
    newpath   = oldparent + newname
    return false unless FileUtils.move(oldpath.to_s,newpath.to_s)
    userfile.name = newname
    userfile.save
    true
  end

end
