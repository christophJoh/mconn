#
# MConn Framework
# https://www.github.com/livespotting/mconn
#
# @copyright 2015 Livespotting Media GmbH
# @license Apache-2.0
#
# @author Christoph Johannsdotter [c.johannsdotter@livespottingmedia.com]
# @author Jan Stabenow [j.stabenow@livespottingmedia.com]
#

async = require("async")
fs = require("fs")
Q = require("q")
zookeeper = require('node-zookeeper-client')

logger = require("../classes/Logger")("ZookeeperHandler")

# Wrapper for node-zookeeper-client module, extends original functionality with promises, namespaces and custom event-listeners
#
class ZookeeperHandler

  # base node of zookeeper data
  @namespace: -> process.env.MCONN_ZK_PATH

  # zookeeper client, will be generated on registerEvents()
  @client: null

  # member id for leader election
  @memberId: null

  # flag that this member is the master
  @isMaster: false

  # serverdata
  @serverdata: null

  # name of this server
  @servername: null

  # connect client to zookeeper server
  #
  # @return [Promise]
  #
  @connect: =>
    logger.debug("INFO", "Connect to \"" + process.env.MCONN_ZK_HOSTS + "\"")
    deferred = Q.defer()
    @client.connect()
    setTimeout =>
      if @client.state.name is "DISCONNECTED"
        logger.error("Zookeeper is unreachable \"" + process.env.MCONN_ZK_HOSTS + "\"")
    , 10000
    deferred.resolve()
    return deferred.promise

  # create an empty zookeeperPath if it not exists
  #
  # @param [String] path of the zookeeper node
  #
  @createPathIfNotExist: (path) ->
    deferred = Q.defer()
    @exists(path)
    .then (exists) =>
      if (exists)
        return Q.resolve()
      else
        logger.info("Create node \"#{path}\"")
        return @createNode(path,new Buffer(""), zookeeper.ACL.OPEN, zookeeper.CreateMode.PERSISTENT)
    .then ->
      deferred.resolve()
    .catch (error) ->
      logger.error("Error checking if path exists \"" + error + "\"")
      deferred.resolve()
    deferred.promise

  # get masterdata from zookeeper
  #
  # @return [Promise] resolves with masterdata
  #
  @getMaster: =>
    logger.debug("INFO", "Fetching data from leading master")
    deferred = Q.defer()
    @getData("master").then (data) ->
      deferred.resolve(data)
    .catch (error) ->
      deferred.reject(error)
    deferred.promise

  # set data of a node
  #
  # @param [String] path path of zookeepernode, namespace will be prepended automatically
  # @param [Object] data data to write to zookeeper node
  # @param [Number] version version
  # @return [Promise] resolves with stat
  #
  @setData: (path, data, version = -1) =>
    logger.debug("INFO", "Write data \"#{JSON.stringify(data)}\" to node \"#{path}\"")
    deferred = Q.defer()
    @client.setData @namespace() + "/" + path, new Buffer(JSON.stringify(data)), version,  (error, stat) ->
      if error
        logger.error(error)
        deferred.reject(error)
      else
        deferred.resolve(stat)

    deferred.promise

  # get data from zookeeper node
  #
  # @param [String] path path of zookeepernode, namespace will be prepended automatically
  # @return [Promise] resolves with data
  #
  @getData: (path) =>
    logger.debug("INFO", "Fetching data from namespace \"" + @namespace() + "/" + path + "\"")
    deferred = Q.defer()
    @client.getData @namespace() + "/" + path,  (error, data, stat) ->
      if error
        logger.error(error)
        deferred.reject(error)
      else
        try
          if data.toString()
            data = JSON.parse(data.toString("utf-8"))
          else
            data = ""
          deferred.resolve(data)
        catch error
          logger.error(error)
          deferred.reject(error)
    deferred.promise

  # create root node of zookeeper store, if it not exists
  #
  # @return [Promise]
  #
  @createNamespace: ->
    logger.debug("INFO", "Create namespace if required")
    self = @
    deferred = Q.defer()
    self.client.exists self.namespace(), (error, stat) ->
      if error
        logger.error("Create error on namespace \"" + error.toString() + "\"")
        deferred.reject(error)
      #if stat isnt false then namespace exists
      if (stat)
        deferred.resolve(true)
      else
        #create namespace
        self.client.create self.namespace(), new Buffer(""), zookeeper.ACL.OPEN, zookeeper.CreateMode.PERSISTENT, (error) ->
          if error
            logger.error("Create error on namespace \"" + error.toString() + "\"")
          else
            logger.info("Namespace \"" + self.namespace() + "\" successfully created")
          deferred.resolve()
    return deferred.promise

  # create base structure
  #
  # @return [Promise]
  #
  @createBaseStructure: ->
    logger.debug("INFO", "Create basestructure if required")
    deferred = Q.defer()
    @createPathIfNotExist("leader")
    .then => @createPathIfNotExist("inventory")
    .then => @createPathIfNotExist("jobqueue")
    .catch (error) ->
      logger.info(error)
    .finally ->
      deferred.resolve()
    return deferred.promise

  # check if a given path exists
  #
  # @param [String] path path of zookeepernode, namespace will be prepended automatically
  # @return [Promise] resolves with Boolean (true if path exists, false if not)
  #
  @exists: (path) ->
    logger.debug("INFO", "Check if node \"/#{path}\" exists")
    deferred = Q.defer()
    self = @
    @client.exists self.namespace() + "/" + path, (error, stat) ->
      if error
        logger.error(error)
        deferred.reject(error)
      if (stat)
        deferred.resolve(true)
      else
        deferred.resolve(false)
    deferred.promise

  # remove a given path
  #
  # @param [String] path path of zookeepernode, namespace will be prepended automatically
  # @return [Promise]
  #
  @remove: (path) ->
    logger.debug("INFO", "Remove node \"#{path}\"")
    deferred = Q.defer()
    self = @
    @client.remove self.namespace() + "/" + path, (error) ->
      if error
        logger.error(error)
        deferred.reject(error)
      else
        deferred.resolve(true)
    deferred.promise

  # elect the Master-Server (try to add a masternode, first who succeeds is the master)
  #
  # @return [Promise]
  #
  @electMaster: ->
    JobQueue = require("./JobQueue")
    logger.debug("INFO", "Initiate master election")
    App = require("../App")
    Module = require("./Module")

    #    Module.allModulesLoadedDeferred.promise
    #    .then ->
    #        App.renderApplication()
    #    .catch (error) ->
    #      console.log(error)
    @checkIsMaster().then (ismaster) =>
      if ismaster
        unless @isMaster
          @isMaster = true
          logger.info("This node is the new leading master")
          @recoverJobs().then ->
            Module = require("./Module")
            modules = Module.modules
            for name, module of modules
              module.doSync()
        else
          logger.info("Leading master is still \"localhost\"")
      else
        logger.info("Leading master is not \"localhost\"")

  @getMasterId: =>
    deferred = Q.defer()
    @getChildren("leader").then (members) ->
      ids = []
      for member in members
        id = member.split("_")[1]
        ids.push(id)
      ids.sort()
      deferred.resolve(ids[0])
    deferred.promise

  # check if current server is the master
  #
  # @return [Promise] resolves with Boolean
  #
  @checkIsMaster: =>
    logger.debug("INFO", "Check if the leading master is \"localhost\"")
    deferred = Q.defer()
    @getMasterId().then (id) =>
      if id is @memberId
        deferred.resolve(true)
      else
        deferred.resolve(false)
    deferred.promise

  # get data of the current leading master
  #
  # @return [Promise] resolves with data of leading master
  #
  @getMasterData: =>
    logger.debug("INFO", "Detecting leading master")
    deferred = Q.defer()
    @getMasterId().then (id) =>
      @getData("leader/member_#{id}")
      .then (data) ->
        logger.debug("INFO", "Address from leading master \"member_#{id}\" is \"" + data.serverdata.ip + ":" + data.serverdata.port + "\"")
        deferred.resolve(data)
      .catch (error) ->
        logger.error("Error fetching leader data \"" + error + "\"")
        deferred.resolve(false)
    deferred.promise

  # get children of a path
  #
  # @param [String] path path of zookeepernode, namespace will be prepended automatically
  # @return [Array] array of children
  #
  @getChildren: (path) =>
    deferred = Q.defer()
    @client.getChildren @namespace() + "/" + path, (error, children, stat) ->
      if (error)
        deferred.reject(error)
      else
        deferred.resolve(children)
    deferred.promise

  # recover jobs from zookeeper
  #
  # @return [Promise]
  #
  @recoverJobs: =>
    logger.debug("INFO", "Initiate recovering of jobs")
    deferred = Q.defer()
    JobQueue = require("./JobQueue")
    Job = require("./Job")
    Module = require("./Module")
    logger.debug("INFO", "wait for all modules to be loaded")
    Module.allModulesLoadedDeferred.promise
    .then =>
      logger.debug("INFO", "Start recovering jobs")
      @client.getChildren @namespace() + "/jobqueue", (error, children, stat) =>
        # todo, move the following code to JobQueue as recovery method
        logger.info("Recovering \"#{children.length}\" jobs")
        if children.length is 0 then deferred.resolve()
        async.each(children, (c, callback) =>
          @getData("jobqueue/" + c)
          .then (data) ->
            logger.info("Recovering unfinished job \"#{c}\"")
            JobQueue.add(Job.load(data), recovery = true)
            callback()
          .catch (error) ->
            logger.error("Error on leading master processes \"" + error + error.stack + "\"")
          (result) ->
            logger.info("\"#{children.length}\" prior jobs recovered")
            deferred.resolve()
        )

    .catch (error) ->
      logger.error(error)
    deferred.promise

  # handler on zookeeper authentication failure, exit the application since it cannot work without zookeeper connection
  #
  @authenticationFailedHandler: ->
    logger.error("Zookeeper-Session authentication failed, application stop, please fix and restart...")

  # handler if read only connection to zookeeper is established
  #
  @connectedReadOnlyHandler: ->
    logger.error("Zookeeper connected in readonly modus, most functions of MConn will not work")

  # handler on event 'session expired'
  #
  @expiredHandler: ->
    logger.error("Zookeeper-Session has expired, closing application")
    process.exit()

  # method to execute on connection
  #
  @connectedHandler: =>
    logger.debug("INFO", "Initiate watcher on node \"/leader\"")
    #start watcher on leader-folder /leader for new registered servers
    @createNamespace()
    .then =>
      @createBaseStructure()
    .then =>
      @watchLeader()
      @registerMember()

  # handler on disconenct
  #
  @disconnectedHandler: =>
    logger.error("Zookeeper Connection closed, trying to reconnect...")
    @connect() #reconnecthg pull

  # register additional events on zookeeper client
  #
  @registerEvents: =>
    logger.debug("INFO", "Initiate connection handlings")
    @client = if process.env.MCONN_ZK_HOSTS
      zookeeper.createClient(process.env.MCONN_ZK_HOSTS,
        {
          sessionTimeout: parseInt(process.env.MCONN_ZK_SESSION_TIMEOUT),
          spinDelay: parseInt(process.env.MCONN_ZK_SPIN_DELAY),
          retries: parseInt(process.env.MCONN_ZK_RETRIES)
        })
    # core events
    @client.on "authenticationFailed", @authenticationFailedHandler
    @client.on "connectedReadOnly", @connectedReadOnlyHandler
    @client.on "expired", @expiredHandler
    @client.on "connected", @connectedHandler
    @client.on "disconnected", @disconnectedHandler

    # own events
    @client.on "member_registered", ->
      App = require("../App")
      App.initModules()
      .then ->
        App.startWebserver()

  # create a new node on zookeeper under /leader as ephemeral to register this container as running origin server
  #
  # @return [Promise]
  #
  @registerMember: =>
    logger.debug("INFO", "Register new server on node \"/leader\"")
    deferred = Q.defer()
    @serverdata = new Object()
    #ip and port from where the docker-container or application is reachable FROM OUTSIDE
    @serverdata.ip = process.env.MCONN_HOST
    @serverdata.port = process.env.MCONN_PORT
    @serverdata.serverurl = "http://" + @serverdata.ip + ":" + @serverdata.port
    @servername = @serverdata.ip + "-" + @serverdata.port + "-" + require("os").hostname()

    transaction = @client.transaction()
    transaction.create(@namespace() + "/leader/member_", new Buffer(JSON.stringify({@serverdata})), zookeeper.ACL.OPEN, zookeeper.CreateMode.EPHEMERAL_SEQUENTIAL)
    transaction.commit (error, results) =>
      if error
        logger.error(error)
        deferred.reject(error)
      else
        unless results[0]?.path? and results[0].path.split("_")[1]? then logger.error("error on member-registration: could not fetch created memberid")
        else
          @memberId = results[0].path.split("_")[1]
          logger.info("New leading master generated with id \"#{@memberId}\"")
          @client.emit "member_registered"
        deferred.resolve()
    deferred.promise

  # watch /leader node for changes and add event, if change detected
  #
  @watchLeader: ->
    logger.debug("INFO", "Detect changes on node \"/leader\"")
    @client.getChildren @namespace() + "/leader", ((event) =>
      @electMaster()
      @watchLeader()
      return
    ), (error, children, stat) ->
      if error
        logger.error(error)
        return
      return

  # wrapper for zookeeper client
  #
  # @param [String] path  path of zookeepernode, namespace will be prepended automatically
  # @param [Object] content content of th Zookeeper Node
  # @param [String] ACL MODE
  # @param [String] CreateMode of Node
  #
  @createNode: (relativePath, content = new Buffer(""), aclmode = zookeeper.ACL.OPEN, createmode = zookeeper.CreateMode.PERSISTENT, next) =>
    logger.debug("INFO", "Create node \"/" + relativePath + "\"")
    deferred = Q.defer()
    @client.create @namespace() + "/" + relativePath, new Buffer(content), aclmode, createmode, (error) =>
      if error
        logger.error(error)
        deferred.reject(error)
      else
        logger.debug("INFO", "Node \"" + @namespace() + "/" + relativePath + "\" is successfully created")
        deferred.resolve()
      if next? then next(error)
    deferred.promise

module.exports = ZookeeperHandler
