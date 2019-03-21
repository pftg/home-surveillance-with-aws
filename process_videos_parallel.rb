require_relative './person_tracking_service'

tracking_service = PersonTrackingSerivce.new

`aws s3 sync --exclude "*" --include "*.jpg" safe_faces_to_collection/ s3://video-aws/`
Dir['safe_faces_to_collection/**/*.jpg'].each do |snapshot_with_face|
  puts "Add faces to collection from #{snapshot_with_face}"
  tracking_service.addFaceToCollection(snapshot_with_face)
end


puts 'Uploading new video:'

`find new -name '*.avi' | xargs -I % ffmpeg -i "%" -an -vcodec copy "%.mov"`
`find new -name '*.avi' | xargs -I % rm "%"`
`aws s3 sync --exclude "*" --include "*.mov" new/ s3://video-aws/`

puts 'Done'

video_to_process = Dir['new/**/*.mov']

video_to_process.each_slice(15) do |videos|

  puts 'Schedule next portion'

  jobs = videos.each_with_object({}) do |video, memo|
    puts "Schedule analyze of #{video}"
    memo[video] = tracking_service.schedule_search_face(video)
  end

  pp jobs

  sleep 10

  puts 'Check results'

  jobs.each_pair do |video_path, job_id|
    puts "Checking #{video_path} : #{job_id}"
    found_faces_response = tracking_service.search_face_job_result(job_id)
    persons = tracking_service.find_new_persons(found_faces_response)

    next if persons.empty?

    persons.each do |person|
      tracking_service.snapshot_face_for(person, video_path)
    end
  end
end