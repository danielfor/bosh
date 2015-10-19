require 'spec_helper'

module Bosh::Director
  describe Jobs::DeleteOrphanDisks do

    describe '.enqueue' do
      let(:job_queue) { instance_double(JobQueue) }

      it 'enqueues a DeleteOrphanDisks job' do
        fake_orphan_disk_cids = ['fake-cid-1', 'fake-cid-2']

        expect(job_queue).to receive(:enqueue).with('fake-username', Jobs::DeleteOrphanDisks, 'delete orphan disks', [fake_orphan_disk_cids])
        Jobs::DeleteOrphanDisks.enqueue('fake-username', fake_orphan_disk_cids, job_queue)
      end

      it 'errors if disk is not orphaned' do
        persistent_disk_cid = Models::PersistentDisk.make.disk_cid
        expect do
          Jobs::DeleteOrphanDisks.enqueue(nil, [persistent_disk_cid], JobQueue.new)
        end.to raise_error(DeletingPersistentDiskError)
      end
    end

    describe '#perform' do
      let(:event_log){ EventLog::Log.new }
      let(:cloud){ instance_double(Bosh::Cloud) }

      before do
        Bosh::Director::Models::OrphanDisk.make(disk_cid: 'fake-cid-1')
        Bosh::Director::Models::OrphanDisk.make(disk_cid: 'fake-cid-2')

        allow(Config).to receive(:event_log).and_return(event_log)
        allow(event_log).to receive(:begin_stage)

        allow(Config).to receive(:cloud).and_return(cloud)
      end

      context 'when deleting a disk' do
        it 'logs and returns the result' do
          expect(event_log).to receive(:begin_stage).with('Deleting orphaned disks', 2)
          allow(cloud).to receive(:delete_disk)

          delete_orphan_disks = Jobs::DeleteOrphanDisks.new(['fake-cid-1', 'fake-cid-2'])
          expect_any_instance_of(ThreadPool).to receive(:process).twice.and_call_original
          result = delete_orphan_disks.perform

          expect(result).to eq('orphaned disk(s) fake-cid-1, fake-cid-2 deleted')
          expect(Bosh::Director::Models::OrphanDisk.all).to be_empty
        end
      end

      context 'when deleting a disk that has already been deleted' do
        it 'logs the error to the event log and returns the result' do
          allow(cloud).to receive(:delete_disk).twice.and_raise(Bosh::Clouds::DiskNotFound.new(false))
          expect(event_log).to receive(:begin_stage).with('Deleting orphaned disks', 1)
          allow(event_log).to receive(:log_entry)

          expect(event_log).to receive(:log_entry) do |entry_hash|
            expect(entry_hash.values).to include 'Deleting orphaned disk fake-cid-1'
          end

          expect(event_log).to receive(:log_entry) do |entry_hash|
            expect(entry_hash.values).to include 'Disk Not Found in IaaS'
          end

          delete_orphan_disks = Jobs::DeleteOrphanDisks.new(['fake-cid-1'])
          result = delete_orphan_disks.perform

          expect(result).to eq('orphaned disk(s) fake-cid-1 deleted')
        end
      end

      context 'when director was unable to delete a disk' do
        it 're-raises the error' do
          allow(cloud).to receive(:delete_disk).and_raise(Exception.new('Bad stuff happened!'))

          delete_orphan_disks = Jobs::DeleteOrphanDisks.new(['fake-cid-1', 'fake-cid-2'])
          expect {
            delete_orphan_disks.perform
          }.to raise_error Exception, 'Bad stuff happened!'
        end
      end
    end
  end
end
