require 'json'
require 'pathname'
require 'fileutils'

class PersonTrackingSerivce

  def find_new_persons_in(video_path)
    puts "Schedule face search #{video_path}"
    found_faces_response = search_faces_in_video(video_path)
    puts "Process results from face search #{video_path}"
    find_new_persons(found_faces_response)
  end

  def search_faces_in_video(video_path)
    job_id = schedule_search_face(video_path)
    search_face_job_result(job_id)
  end

  def get_persons_tracking(video_name_on_s3)
    job_id = schedule_persons_tracking(video_name_on_s3)
    persons_tracking_job_result(job_id)
  end

  def snapshot_face_for(person_details, video_path)
    t = person_details['Timestamp']
    result = "output/#{video_path}.#{t}.jpg"


    FileUtils.mkdir_p(Pathname.new(result).parent.to_s)

    `ffmpeg -y -i "#{video_path}" -ss #{t / 1000}.#{t % 1000} -vframes 1 "#{result}"`

    result
  end

  def addFaceToCollection(snapshot_with_face)
    image_name = Pathname.new(snapshot_with_face).basename
    # `aws s3 cp "#{image_name}" "s3://video-aws/"`
    `aws rekognition index-faces --image '{"S3Object":{"Bucket":"video-aws","Name":"#{image_name}"}}' --collection-id "trusted" --quality-filter "AUTO" --detection-attributes "ALL"`
  end

  def find_new_persons(found_faces_response)
    existed_in_collection_persons = found_faces_response['Persons']
                                        .select { |person_wrapper| !person_wrapper['FaceMatches'].nil? && !person_wrapper['FaceMatches'].empty? }
                                        .map { |person_wrapper| person_wrapper['Person']['Index'] }
                                        .uniq

    non_existed_in_collection_persons = found_faces_response['Persons']
                                            .select { |person_wrapper| person_wrapper['Person']['Face'] && (person_wrapper['FaceMatches'].nil? || person_wrapper['FaceMatches'].empty?) }

    person_index_for_non_indexed = non_existed_in_collection_persons.map do |person_wrapper|
      person_wrapper['Person']['Index']
    end.uniq

    puts 'Find matched persons'

    pp existed_in_collection_persons

    puts 'Find to match persons'

    puts 'Persons with faces:'
    pp person_index_for_non_indexed

    puts 'Faces of new Persons'

    pp persons_to_index = person_index_for_non_indexed - existed_in_collection_persons

    persons = non_existed_in_collection_persons
                  .select { |person| persons_to_index.include?(person['Person']['Index']) }

    puts '=' * 20

    persons
  end

  def schedule_persons_tracking(video_path)
    video_name_on_s3 = video_path.sub 'new/', ''
    response = `aws rekognition start-person-tracking --video 'S3Object={Bucket="video-aws",Name="#{video_name_on_s3}"}'`

    JSON.parse(response)['JobId']
  end

  def schedule_search_face(video_path)
    video_name_on_s3 = video_path.sub 'new/', ''
    response = `aws rekognition start-face-search --video '{"S3Object":{"Bucket":"video-aws","Name":"#{video_name_on_s3}"}}' --collection-id "trusted" --face-match-threshold 90`

    JSON.parse(response)['JobId']
  end

  def persons_tracking_job_result(job_id)
    500.times do
      get_response = `aws rekognition get-person-tracking --job-id #{job_id}`
      result = JSON.parse(get_response)
      if result['JobStatus'] == 'IN_PROGRESS'
        sleep 10
      else
        return result
      end
    end

    throw TimeoutError
  end

  def search_face_job_result(job_id)
    50.times do
      get_response = `aws rekognition get-face-search --job-id #{job_id}`
      res = JSON.parse(get_response)
      if res['JobStatus'] == 'IN_PROGRESS'
        sleep 10
      else
        return res
      end
    end

    throw TimeoutError
  end
end
