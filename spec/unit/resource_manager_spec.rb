# coding: UTF-8

require "spec_helper"
require "dea/resource_manager"
require "dea/instance_registry"
require "dea/staging_task_registry"
require "dea/staging_task"
require "dea/instance"
require "dea/bootstrap"

describe Dea::ResourceManager do
  let(:memory_mb) { 600 }
  let(:memory_overcommit_factor) { 4 }
  let(:disk_mb) { 4000 }
  let(:disk_overcommit_factor) { 2 }
  let(:nominal_memory_capacity) { memory_mb * memory_overcommit_factor }
  let(:nominal_disk_capacity) { disk_mb * disk_overcommit_factor }

  let(:bootstrap) { Dea::Bootstrap.new }
  let(:instance_registry) { Dea::InstanceRegistry.new }
  let(:staging_registry) { Dea::StagingTaskRegistry.new }

  let(:manager) do
    Dea::ResourceManager.new(instance_registry, staging_registry, {
      "memory_mb" => memory_mb,
      "memory_overcommit_factor" => memory_overcommit_factor,
      "disk_mb" => disk_mb,
      "disk_overcommit_factor" => disk_overcommit_factor
    })
  end

  describe "#remaining_memory" do
    context "when no instances or staging tasks are registered" do
      it "returns the full memory capacity" do
        manager.remaining_memory.should eql(memory_mb * memory_overcommit_factor)
      end
    end

    context "when instances are registered" do
      before do
        instance_registry.register(Dea::Instance.new(bootstrap, "limits" => { "mem" => 1 }).tap { |i| i.state = "BORN" })
        instance_registry.register(Dea::Instance.new(bootstrap, "limits" => { "mem" => 2 }).tap { |i| i.state = "STARTING" })
        instance_registry.register(Dea::Instance.new(bootstrap, "limits" => { "mem" => 4 }).tap { |i| i.state = "RUNNING" })
        instance_registry.register(Dea::Instance.new(bootstrap, "limits" => { "mem" => 8 }).tap { |i| i.state = "STOPPING" })
        instance_registry.register(Dea::Instance.new(bootstrap, "limits" => { "mem" => 16 }).tap { |i| i.state = "STOPPED" })
        instance_registry.register(Dea::Instance.new(bootstrap, "limits" => { "mem" => 32 }).tap { |i| i.state = "CRASHED" })
        instance_registry.register(Dea::Instance.new(bootstrap, "limits" => { "mem" => 64 }).tap { |i| i.state = "DELETED" })

        staging_registry.register(Dea::StagingTask.new(bootstrap, nil, {}))
      end

      it "returns the correct remaining memory" do
        manager.remaining_memory.should eql(nominal_memory_capacity - (1 + 2 + 4 + 8 + 1024))
      end
    end
  end

  describe "#remaining_disk" do
    context "when no instances are registered" do
      let(:reserved_instance_disk) { 0 }
      let(:reserved_staging_disk) { 0 }

      it "returns the full disk capacity" do
        manager.remaining_disk.should eql(nominal_disk_capacity)
      end
    end

    context "when instances are registered" do
      before do
        instance_registry.register(Dea::Instance.new(bootstrap, "limits" => { "disk" => 1 }).tap { |i| i.state = "BORN" })
        instance_registry.register(Dea::Instance.new(bootstrap, "limits" => { "disk" => 2 }).tap { |i| i.state = "STARTING" })
        instance_registry.register(Dea::Instance.new(bootstrap, "limits" => { "disk" => 4 }).tap { |i| i.state = "RUNNING" })
        instance_registry.register(Dea::Instance.new(bootstrap, "limits" => { "disk" => 8 }).tap { |i| i.state = "STOPPING" })
        instance_registry.register(Dea::Instance.new(bootstrap, "limits" => { "disk" => 16 }).tap { |i| i.state = "STOPPED" })
        instance_registry.register(Dea::Instance.new(bootstrap, "limits" => { "disk" => 32 }).tap { |i| i.state = "CRASHED" })
        instance_registry.register(Dea::Instance.new(bootstrap, "limits" => { "disk" => 64 }).tap { |i| i.state = "DELETED" })

        staging_registry.register(Dea::StagingTask.new(bootstrap, nil, {}))
      end

      it "returns the correct remaining disk" do
        manager.remaining_disk.should eql(nominal_disk_capacity - (1 + 2 + 4 + 8 + 32 + 2048))
      end
    end
  end

  describe "app_id_to_count" do
    before do
      instance_registry.register(Dea::Instance.new(bootstrap, "application_id" => "a").tap { |i| i.state = "BORN" })
      instance_registry.register(Dea::Instance.new(bootstrap, "application_id" => "b").tap { |i| i.state = "STARTING" })
      instance_registry.register(Dea::Instance.new(bootstrap, "application_id" => "b").tap { |i| i.state = "STARTING" })
      instance_registry.register(Dea::Instance.new(bootstrap, "application_id" => "c").tap { |i| i.state = "RUNNING" })
      instance_registry.register(Dea::Instance.new(bootstrap, "application_id" => "c").tap { |i| i.state = "RUNNING" })
      instance_registry.register(Dea::Instance.new(bootstrap, "application_id" => "c").tap { |i| i.state = "RUNNING" })
      instance_registry.register(Dea::Instance.new(bootstrap, "application_id" => "d").tap { |i| i.state = "STOPPING" })
      instance_registry.register(Dea::Instance.new(bootstrap, "application_id" => "e").tap { |i| i.state = "STOPPED" })
      instance_registry.register(Dea::Instance.new(bootstrap, "application_id" => "f").tap { |i| i.state = "CRASHED" })
      instance_registry.register(Dea::Instance.new(bootstrap, "application_id" => "g").tap { |i| i.state = "DELETED" })
    end

    it "should return all registered instances regardless of state" do
      manager.app_id_to_count.should == {
        "a" => 1,
        "b" => 2,
        "c" => 3,
        "d" => 1,
        "e" => 1,
        "f" => 1,
        "g" => 1,
      }
    end
  end

  describe "number_reservable" do
    let(:memory_mb) { 600 }
    let(:memory_overcommit_factor) { 1 }
    let(:disk_mb) { 4000 }
    let(:disk_overcommit_factor) { 1 }

    context "when there is not enough memory to reserve any" do
      it "is 0" do
        manager.number_reservable(10_000, 1).should == 0
      end
    end

    context "when there is not enough disk to reserve any" do
      it "is 0" do
        manager.number_reservable(1, 10_000).should == 0
      end
    end

    context "when there are enough resources for a single reservation" do
      it "is 1" do
        manager.number_reservable(500, 3000).should == 1
      end
    end

    context "when there are enough resources for many reservations" do
      it "is correct" do
        manager.number_reservable(200, 1500).should == 2
        manager.number_reservable(200, 1000).should == 3
      end
    end

    context "when 0 resources are requested" do
      it "returns 0" do
        manager.number_reservable(0, 0).should == 0
      end
    end
  end

  describe "available_memory_ratio" do
    before do
      instance_registry.register(Dea::Instance.new(bootstrap, "limits" => { "mem" => 512 }).tap { |i| i.state = "RUNNING" })
      staging_registry.register(Dea::StagingTask.new(bootstrap, nil, {}))
    end

    it "is the ratio of available memory to total memory" do
      manager.available_memory_ratio.should == 1 - (512.0 + 1024.0) / nominal_memory_capacity
    end
  end

  describe "available_disk_ratio" do
    before do
      instance_registry.register(Dea::Instance.new(bootstrap, "limits" => { "disk" => 512 }).tap { |i| i.state = "RUNNING" })
      staging_registry.register(Dea::StagingTask.new(bootstrap, nil, {}))
    end

    it "is the ratio of available disk to total disk" do
      manager.available_disk_ratio.should == 1 - (512.0 + 2048.0) / nominal_disk_capacity
    end
  end

  describe "could_reserve?" do
    before do
      instance_registry.register(Dea::Instance.new(bootstrap, "limits" => { "mem" => 512, "disk" => 1024 }).tap { |i| i.state = "RUNNING" })
      staging_registry.register(Dea::StagingTask.new(bootstrap, nil, {}))

      @remaining_memory = nominal_memory_capacity - 512 - 1024
      @remaining_disk = nominal_disk_capacity - 1024 - 2048
    end

    context "when the given amounts of memory and disk are available (including extra 'headroom' memory)" do
      it "can reserve" do
        manager.could_reserve?(@remaining_memory - 1, @remaining_disk - 1).should be_true
      end
    end

    context "when too much memory is being used" do
      it "can't reserve" do
        manager.could_reserve?(@remaining_memory, 1).should be_false
      end
    end

    context "when too much disk is being used" do
      it "can't reserve" do
        manager.could_reserve?(1, @remaining_disk).should be_false
      end
    end
  end
end
