package main

import (
    "os"
    "time"
    "flag"
    "syscall"
    "os/signal"
    "io/ioutil"
    "sync"

    "github.com/hashicorp/go-reap"
)

var (
    version string

    logstash = flag.String("logstash", "127.0.0.1:10001", "Logstash 'host:port' (UDP), if set to '' then sending logs is disabled.")

    storeType = flag.String("storeType", "", "zookeeper, consul or etcd.")
    storeConnection = flag.String("storeConnection", "", "Key-value store connection string.")
    storeKey = flag.String("storeKey", "/vamp/gateways/haproxy/1.6", "HAProxy configuration store key.")

    configurationPath = flag.String("configurationPath", "/usr/local/vamp/", "HAProxy configuration path.")
    configurationBasicFile = flag.String("configurationBasicFile", "haproxy.basic.cfg", "Basic HAProxy configuration.")

    scriptPath = flag.String("scriptPath", "/usr/local/vamp/", "HAProxy validation and reload script path.")

    timeout = flag.Int("retryTimeout", 5, "Default retry timeout in seconds.")

    logo = flag.Bool("logo", true, "Show logo.")
    help = flag.Bool("help", false, "Print usage.")
    debug = flag.Bool("debug", false, "Switches on extra log statements.")

    retryTimeout = 5 * time.Second
    logger = CreateLogger()
)

func Logo() string {
    return `
██╗   ██╗ █████╗ ███╗   ███╗██████╗
██║   ██║██╔══██╗████╗ ████║██╔══██╗
██║   ██║███████║██╔████╔██║██████╔╝
╚██╗ ██╔╝██╔══██║██║╚██╔╝██║██╔═══╝
 ╚████╔╝ ██║  ██║██║ ╚═╝ ██║██║
  ╚═══╝  ╚═╝  ╚═╝╚═╝     ╚═╝╚═╝
                       gateway agent
                       version ` + version + `
                       by magnetic.io
                                      `
}

type Watcher interface {
    Watch(onChange func([]byte) error)
}

func main() {

    flag.Parse()

    if *logo {
        logger.Notice(Logo())
    }

    if *help {
        flag.Usage()
        return
    }

    if len(*storeType) == 0 {
        logger.Panic("Key-value store type not speciffed.")
        return
    }

    if len(*storeConnection) == 0 {
        logger.Panic("Key-value store servers not speciffed.")
        return
    }

    if _, err := os.Stat(*configurationPath + *configurationBasicFile); os.IsNotExist(err) {
        logger.Panic("No basic HAProxy configuration: ", *configurationPath, *configurationBasicFile)
        return
    }

    retryTimeout = time.Duration(*timeout) * time.Second

    logger.Notice("Starting Vamp Gateway Agent")

    var reapLock sync.RWMutex
    haProxy := HAProxy{
        ScriptPath:    *scriptPath,
        BasicConfig:        *configurationPath + *configurationBasicFile,
        ConfigFile:         *configurationPath + "haproxy.cfg",
        LogSocket:          *configurationPath + "haproxy.log.sock",
        reapLock:      &reapLock,
    }

    if _, err := os.Stat(haProxy.ConfigFile); os.IsNotExist(err) {
        basic, err := ioutil.ReadFile(haProxy.BasicConfig)
        if err != nil {
            logger.Panic("Cannot read basic HAProxy configuration: ", haProxy.BasicConfig)
            return
        }
        ioutil.WriteFile(haProxy.ConfigFile, basic, 0644)
    }

    // Waiter keeps the program from exiting instantly.
    waiter := make(chan bool)

    cleanup := func() {
        os.Remove(haProxy.LogSocket)
    }

    // Wait for died children to avoid zombies
    if reap.IsSupported() {
        logger.Notice("Automatically reaping child processes")
        pids := make(reap.PidCh, 1)
        errors := make(reap.ErrorCh, 1)
        go func() {
            for {
                select {
                case pid := <-pids:
                    logger.Notice("Reaped child process %d", pid)
                case err := <-errors:
                    logger.Panic("Error reaping child process: %v", err)
                }
            }
        }()
        go reap.ReapChildren(pids, errors, nil, &reapLock)
    } else {
        logger.Notice("Child process reaping is not supported on this platform.")
    }

    // Catch a CTR+C exits so the cleanup routine is called.
    c := make(chan os.Signal, 1)
    signal.Notify(c, os.Interrupt)
    signal.Notify(c, syscall.SIGTERM)
    go func() {
        <-c
        cleanup()
        os.Exit(1)
    }()

    defer cleanup()

    haProxy.Init()
    haProxy.Run()

    keyValueWatcher := keyValueWatcher()

    if keyValueWatcher == nil {
        return
    }

    go keyValueWatcher.Watch(haProxy.Reload)

    waiter <- true
}

func keyValueWatcher() Watcher {
    if *storeType == "etcd" {
        return &Etcd{
            ConnectionString: *storeConnection,
            Path: *storeKey,
        }
    } else if *storeType == "consul" {
        return &Consul{
            ConnectionString: *storeConnection,
            Path: *storeKey,
        }
    } else if *storeType == "zookeeper" {
        return &ZooKeeper{
            ConnectionString: *storeConnection,
            Path: *storeKey,
        }
    } else {
        logger.Panic("Key-value store type not supported: ", *storeType)
        return nil
    }
}
