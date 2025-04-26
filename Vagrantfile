# -*- mode: ruby -*-
# vi: set ft=ruby :

ENV['ANSIBLE_CALLBACK_RESULT_FORMAT'] = 'yaml'

DEFAULT_MACHINE = {
  :domain => 'internal',
  :box => 'bento/ubuntu-24.04/202502.21.0',
  :cpus => 1,
  :memory => 1024,
  :disks => {},
  :networks => {},
  :intnets => {},
  :forwarded_ports => [],
  :modifyvm => []
}

GROUPS = {
  :iscsi => {
    :'web-iscsi-01' => {
      :disks => { :'web-iscsi-01-disk01' => '20GB' },
      :intnets => {
        :'web-iscsi01' => { :ip => '10.131.0.11' },
        :'web-iscsi02' => { :ip => '10.132.0.11' },
      },
      :networks => { :private_network => { :ip => '192.168.56.11' } },
    },
    :'web-iscsi-02' => {
      :disks => { :'web-iscsi-02-disk01' => '20GB' },
      :intnets => {
        :'web-iscsi01' => { :ip => '10.131.0.12' },
        :'web-iscsi02' => { :ip => '10.132.0.12' },
      },
      :networks => { :private_network => { :ip => '192.168.56.12' } },
    },
  },
  :backend => {
    :'web-backend-01' => {
      :memory => 2048,
      :intnets => {
        :'web-iscsi01' => { :ip => '10.131.0.21' },
        :'web-iscsi02' => { :ip => '10.132.0.21' },
      },
      :networks => { :private_network => { :ip => '192.168.56.21' } },
    },
    :'web-backend-02' => {
      :memory => 2048,
      :intnets => {
        :'web-iscsi01' => { :ip => '10.131.0.22' },
        :'web-iscsi02' => { :ip => '10.132.0.22' },
      },
      :networks => { :private_network => { :ip => '192.168.56.22' } },
    },
    :'web-backend-03' => {
      :memory => 2048,
      :intnets => {
        :'web-iscsi01' => { :ip => '10.131.0.23' },
        :'web-iscsi02' => { :ip => '10.132.0.23' },
      },
      :networks => { :private_network => { :ip => '192.168.56.23' } },
    },
  },
  :db => {
    :'web-db-01' => {
      :networks => { :private_network => { :ip => '192.168.56.31' } },
    },
  },
  :lb => {
    :'web-lb-01' => {
      :networks => { :private_network => { :ip => '192.168.56.41' } },
    },
    :'web-lb-02' => {
      :networks => { :private_network => { :ip => '192.168.56.42' } },
    },
  }
}
MACHINES = GROUPS.values.each_with_object({}) { |m, o| o.merge!(m) }
ANSIBLE_GROUPS = GROUPS.to_h{ |k, v| [k, v.keys()] }
ANSIBLE_HOSTVARS = MACHINES.each_with_object({}) {
  |kv, obj| obj[kv[0]] = {
    'ip_address' => kv[1][:networks][:private_network][:ip],
    'ip_address_iscsi1' => kv[1].fetch(:intnets, {}).key?(:'web-iscsi01') ?
      kv[1][:intnets][:'web-iscsi01'][:ip] : nil,
    'ip_address_iscsi2' => kv[1].fetch(:intnets, {}).key?(:'web-iscsi02') ?
      kv[1][:intnets][:'web-iscsi02'][:ip] : nil,
  }
}

def provisioned?(host_name)
  return File.exist?('.vagrant/machines/' + host_name.to_s +
    '/virtualbox/action_provision')
end

Vagrant.configure('2') do |config|
  MACHINES.each do |host_name, host_config|
    host_config = DEFAULT_MACHINE.merge(host_config)
    config.vm.define host_name do |host|
      host.vm.box = host_config[:box]
      if not provisioned?(host_name)
        host.vm.host_name = host_name.to_s + '.' + host_config[:domain].to_s
      end

      host.vm.provider :virtualbox do |vb|
        vb.cpus = host_config[:cpus]
        vb.memory = host_config[:memory]

        if !host_config[:modifyvm].empty?
          vb.customize ['modifyvm', :id] + host_config[:modifyvm]
        end
      end

      host_config[:disks].each do |name, size|
        host.vm.disk :disk, name: name.to_s, size: size
      end

      host_config[:intnets].each do |name, intnet|
        intnet[:virtualbox__intnet] = name.to_s
        host.vm.network(:private_network, **intnet)
      end
      host_config[:networks].each do |network_type, network_args|
        host.vm.network(network_type, **network_args)
      end
      host_config[:forwarded_ports].each do |forwarded_port|
        host.vm.network(:forwarded_port, **forwarded_port)
      end

      if MACHINES.keys.last == host_name
        host.vm.provision :ansible do |ansible|
          ansible.playbook = 'provision.yml'
          ansible.groups = ANSIBLE_GROUPS
          ansible.host_vars = ANSIBLE_HOSTVARS
          ansible.limit = 'all'
          ansible.compatibility_mode = '2.0'
          ansible.raw_arguments = ['--diff']
          ansible.tags = 'all'
        end
      end

      host.vm.synced_folder '.', '/vagrant', disabled: true
    end
  end
end
