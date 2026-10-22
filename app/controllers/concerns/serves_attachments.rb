# A support ticket's attachment, once the caller has been allowed to see it:
# a redirect to the file rather than the file. Active Storage then serves it
# from its store in chunks (or S3 does), where `send_data file.download` held
# all of it — up to 100 MB — in this process's memory for every download
# (+139 MB measured for a 50 MB video). The link it redirects to expires.
module ServesAttachments
  LINK_EXPIRES_IN = 5.minutes

  private

  def redirect_to_attachment(file)
    redirect_to rails_blob_path(file, disposition: "inline", expires_in: LINK_EXPIRES_IN)
  end
end
