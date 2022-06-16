require 'spec_helper'

describe NATSSync::Runner do
  subject { NATSSync::Runner.new(sample_config, stdout) }
  let(:stdout) { StringIO.new }
  let(:user_sync_class) { class_double('NATSSync::UsersSync').as_stubbed_const }
  let(:user_sync_instance) { instance_double(NATSSync::UsersSync) }

  describe 'when the runner is created with the sample config file' do
    let(:bosh_config) do
      { 'url' => 'http://127.0.0.1:25555', 'user' => 'admin', 'password' => 'admin', 'client_id' => 'client_id',
        'client_secret' => 'client_secret', 'ca_cert' => 'ca_cert',
        'director_subject_file' => '/var/vcap/data/nats/director-subject',
        'hm_subject_file' => '/var/vcap/data/nats/hm-subject' }
    end
    let(:file_path) { '/var/vcap/data/nats/auth.json' }
    before do
      allow(user_sync_instance).to receive(:execute_users_sync)
      allow(user_sync_class).to receive(:new).and_return(user_sync_instance)
      Thread.new do
        subject.run
      end
      sleep(2)
    end

    it 'should start UsersSync.execute_nats_sync function with the same parameters defined in the file' do
      expect(user_sync_class).to have_received(:new).with(stdout, file_path, bosh_config)
      expect(user_sync_instance).to have_received(:execute_users_sync)
    end

    after do
      subject.stop
    end
  end
end