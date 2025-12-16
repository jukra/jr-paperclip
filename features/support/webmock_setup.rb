require "webmock/cucumber"

# Allow AWS EC2 instance metadata service (used by AWS SDK for credential detection)
# This IP is a standard link-local address used by all major cloud providers
WebMock.disable_net_connect!(
  allow_localhost: true,
  allow: "169.254.169.254"
)
