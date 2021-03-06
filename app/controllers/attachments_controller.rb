class AttachmentsController < ApplicationController
  before_action :authenticate_user!, except: [:index, :show_track, :show, :baked]
  skip_before_action :verify_authenticity_token

  def index
    track = Track.find_by(id: params[:track_id])
    return head(404) unless track.present?

    attachments = track.self_and_rebounds.map do |track|
      track.attachments.preload(:user).map do |a|
        a.attributes.merge({
          artist_name: a.user.artist_name
        })
      end
    end.flatten.sort_by { |attachment| attachment["created_at"] }

    render json: {
      attachments: attachments
    }
  end

  def s3_direct_post
    s3_bucket = s3_resource.bucket(Rails.application.credentials.dig(:aws, :bucket))
    s3_direct_post = s3_bucket.presigned_post(
      key: "audio/#{SecureRandom.uuid}/${filename}",
      success_action_status: '201',
      acl: 'public-read',
      content_length_range: 0..200000000, # 200 MB
      content_type: "application/octet-stream",
      content_disposition: "attachment; filename=\"#{params[:attachmentName]}\""
    )

    url = s3_direct_post.url
    fields = s3_direct_post.fields
    render json: { url: url, fields: fields }, status: :created
  end

  def s3_blob_location
    aws_url = params[:location]

    attachment = Attachment.create!(
      user: current_user,
      url: aws_url,
      track_id: params[:trackId],
      name: params[:attachmentName],
      size_mb: params[:fileSize].to_f
    )

    render json: attachment.attributes.merge({
      artist_name: attachment.user.artist_name
    })
  end

  private

  def s3_resource
    @s3_resource ||= begin
      creds = Aws::Credentials.new(Rails.application.credentials.dig(:aws, :access_key_id), Rails.application.credentials.dig(:aws, :secret_access_key))
      Aws::S3::Resource.new(region: Rails.application.credentials.dig(:aws, :region), credentials: creds)
    end
  end
end
