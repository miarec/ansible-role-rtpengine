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

def test_timeouts(host):
    # converge.yml sets the timeout variables to values that differ from
    # RTPEngine's defaults.
    args = host.process.get(comm="rtpengine").args.split()

    assert "--timeout=61" in args
    assert "--silent-timeout=3601" in args
    assert "--final-timeout=7201" in args
