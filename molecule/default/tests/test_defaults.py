import os
import testinfra.utils.ansible_runner

testinfra_hosts = testinfra.utils.ansible_runner.AnsibleRunner(
    os.environ['MOLECULE_INVENTORY_FILE']).get_hosts('all')

def test_directories(host):
    dirs = [
        "/var/log/rtpengine",
        "/opt/rtpengine",
    ]

    for dir in dirs:
        d = host.file(dir)
        assert d.is_directory
        assert d.exists

def test_files(host):

    files = [
        "/var/log/rtpengine/rtpengine.log"
    ]

    for file in files:
        f = host.file(file)
        assert f.exists
        assert f.is_file

def test_service(host):
    s = host.service("rtpengine")

    assert s.is_enabled
    assert s.is_running


def test_socket(host):
    sockets = [
        "udp://127.0.0.1:2223"
    ]
    for socket in sockets:
        s = host.socket(socket)
        assert s.is_listening