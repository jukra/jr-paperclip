When /^I attach the file "([^"]*)" to "([^"]*)" on S3$/ do |file_path, field|
  # Stub S3 PUT requests for any region and track them
  stub_request(:put, %r{https://paperclip\.s3\.[a-z0-9-]+\.amazonaws\.com/.*})
    .to_return(status: 200, body: "", headers: {})

  step "I attach the file \"#{file_path}\" to \"#{field}\""
end

Then /^the file at "([^"]*)" should be uploaded to S3$/ do |url|
  # Extract the path from the URL (e.g., "//s3.amazonaws.com/paperclip/attachments/original/5k.png")
  # becomes "/attachments/original/5k.png"
  path = url.sub(%r{^//s3\.amazonaws\.com/paperclip}, "")

  # Verify a PUT request was made to S3 with this path
  expect(WebMock).to have_requested(:put, %r{https://paperclip\.s3\.[a-z0-9-]+\.amazonaws\.com#{Regexp.escape(path)}})
end
