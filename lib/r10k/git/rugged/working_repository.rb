require 'r10k/git/rugged'
require 'r10k/git/rugged/base_repository'

class R10K::Git::Rugged::WorkingRepository < R10K::Git::Rugged::BaseRepository

  #  @return [Pathname] The path to this directory
  attr_reader :path

  # @return [Pathname] The path to the Git repository inside of this directory
  def git_dir
    @path + '.git'
  end

  # @param basedir [String] The base directory of the Git repository
  # @param dirname [String] The directory name of the Git repository
  def initialize(basedir, dirname)
    @path = Pathname.new(File.join(basedir, dirname))
    if exist? && git_dir.exist?
      @_rugged_repo = ::Rugged::Repository.new(@path.to_s, :alternates => alternates.to_a)
    end
  end

  # Clone this git repository
  #
  # @param remote [String] The Git remote to clone
  # @param opts [Hash]
  #
  # @options opts [String] :ref The git ref to check out on clone
  # @options opts [String] :reference A Git repository to use as an alternate object database
  #
  # @return [void]
  def clone(remote, opts = {})
    logger.debug1 { "Cloning '#{remote}' into #{@path}" }

    # libgit2/rugged doesn't support cloning a repository and providing an
    # alternate object database, making the handling of :alternates a noop.
    # Unfortunately this means that this method can't really use alternates
    # and running the clone will duplicate all objects in the specified
    # repository. However alternate databases can be handled when an existing
    # repository is loaded, so loading a cloned repo will correctly use
    # alternate object database.
    options = {:credentials => credentials}
    options.merge!(:alternates => [File.join(opts[:reference], 'objects')]) if opts[:reference]
    @_rugged_repo = ::Rugged::Repository.clone_at(remote, @path.to_s, options)

    if opts[:reference]
      alternates << File.join(opts[:reference], 'objects')
    end

    if opts[:ref]
      # todo:  always check out something; since we're fetching a repository we
      # won't populate the working directory.
      checkout(opts[:ref])
    end
  end

  # Check out the given Git ref
  #
  # @param ref [String] The git reference to check out
  # @return [void]
  def checkout(ref)
    logger.debug1 { "Checking out ref '#{ref}' at #{@path}" }
    sha = resolve(ref)

    with_repo do |repo|
      repo.checkout(sha)
      repo.reset(sha, :hard)
    end
  end

  def fetch(remote = 'origin')
    logger.debug1 { "Fetching remote '#{remote}' at #{@path}" }
    options = {:credentials => credentials}
    refspecs = ["+refs/heads/*:refs/remotes/#{remote}/*"]
    results = with_repo { |repo| repo.fetch(remote, refspecs, options) }
    report_transfer(results, remote)
    nil
  end

  def exist?
    @path.exist?
  end

  def head
    resolve('HEAD')
  end

  def alternates
    R10K::Git::Alternates.new(git_dir)
  end

  def origin
    with_repo { |repo| repo.config['remote.origin.url'] }
  end
end
