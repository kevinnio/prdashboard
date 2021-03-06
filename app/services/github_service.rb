class GithubService
  attr_accessor :github, :token

  def initialize(token)
    @token = token
    @github = Github.new oauth_token: token
  end

  def pull_requests(organization)
    Rails.cache.fetch("#{cache_key}/#{organization}/pulls", expires_in: 5.minutes) do
      pulls = []

      repos_for(organization).each do |repo|
        if repo.issues_count > 0
          pull_requests = github.pull_requests.list(user: organization, repo: repo.name, auto_pagination: true)

          pull_requests.each do |pull|
            pulls << PullRequest.new(pull)
          end
        end
      end

      repositories = pulls.map(&:repository).uniq { |e| [e.id] }
      users        = pulls.map(&:user).uniq { |e| [e.id] }

      [pulls, repositories, users]
    end
  end

  def organizations
    orgs = []
    organizations = github.orgs.list

    organizations.each_page do |page|
      page.each do |org|
        orgs << Organization.new(org)
      end
    end

    orgs.sort_by { |org| org.name }
  end

  def diff(params)
    Rails.cache.fetch("#{cache_key}/diff/#{params[:repo]}/#{params[:id]}}", expires_in: 5.minutes) do
      uri = URI("https://api.github.com/repos/#{params[:repo]}/pulls/#{params[:id]}.diff")

      req = Net::HTTP::Get.new(uri)
      req['Authorization'] = "token #{token}"
      req['Accept'] = 'application/vnd.github.v3.diff'

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.request(req)
      end

      res.body
    end
  end

  def create_pull_comment(params)
    user, repo = user_repo(params)
    github.issues.comments.create user, repo, params[:pull], body: params[:text]
  end

  def pull_comments(params)
    comments_list = []
    user, repo = user_repo(params)

    comments = github.issues.comments.list(user, repo, issue_id: params[:pull], auto_pagination: true)

    comments.each do |comment|
      comments_list << Comment.new(comment)
    end

    comments_list
  end

  def merge_pull_request(params, current_user)
    user, repo = user_repo(params)
    github.pull_requests.merge user, repo, params[:id], commit_message: "Merged from PR Dashboard by #{current_user.nickname}"
  end

  def close_pull_request(params, _)
    user, repo = user_repo(params)
    github.pull_requests.update user, repo, params[:id], state: 'closed'
  end

  def pull_mergeable?(params)
    user, repo = user_repo(params)
    pull = github.pull_requests.get user, repo, params[:id]

    pull[:mergeable]
  end

  private

  def repos_for(organization)
    repos = []

    github.repos.list(org: organization, auto_pagination: true).each do |repo|
      repos << OpenStruct.new(name: repo['name'], issues_count: repo['open_issues_count'])
    end

    repos
  end

  def cache_key
    Digest::MD5.hexdigest("#{@token}")
  end

  def user_repo(params)
    info = params[:repo].split('/')
    [info.first, info.last]
  end

end

