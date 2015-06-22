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
chai = require 'chai'
spies = require 'chai-spies'
chai.use spies
expect = chai.expect
Q = require("q")
ZookeeperHandler = require("../src/application/classes/ZookeeperHandler")
check = ( done, f )  ->
  try
    f()
    done()
  catch e
    done(e)

#set env defaults
require("../src/application/App").checkEnvironment()

describe "ErrorHandling", ->

  describe "ZookeeperHandler", ->
    ZookeeperHandler = null
    beforeEach (done)->
      delete require.cache[require.resolve("../src/application/classes/ZookeeperHandler")]
      ZookeeperHandler = require("../src/application/classes/ZookeeperHandler")
      process.env.MCONN_ZK_HOSTS = if process.env.ALIAS_PORT_2181_TCP_ADDR? then process.env.ALIAS_PORT_2181_TCP_ADDR + ":2181" else "127.0.0.1:2181"
      process.env.MCONN_ZK_PATH = "/mconn-dev-errorhandling"
      Q.delay(1000).then -> done()

    describe "@connect()" ,->
      it "should reject with error, if the zookeeper is unreachable", (done) ->
        this.timeout(11000)
        process.env.MCONN_ZK_HOSTS = "any.url:1234"
        ZookeeperHandler.registerEvents()
        ZookeeperHandler.connect()
        .then ->
          check done, ->
            expect(true).equal(false, "should have rejected with error")
        .catch (error) ->
          check done, ->
            expect(error).equal("Zookeeper is unreachable \"" + process.env.MCONN_ZK_HOSTS + "\"")

      it "should should not reject with error, if zookeeper is reachable", (done) ->
        ZookeeperHandler.registerEvents()
        ZookeeperHandler.connect()
        .then ->
          check done, ->
            expect(true).equal(true, "resolved")
        .catch (error) ->
          check done, ->
            expect(error).equal(false, "should not reject with error")

    describe "@createPathIfNotExists() (never rejects)", ->
      it "should not reject with error if path exists", (done) ->
        ZookeeperHandler.registerEvents()
        ZookeeperHandler.connect()
          .then ->
            ZookeeperHandler.createNode("testnode")
          #using finally because createNode could reject
          .finally ->
            ZookeeperHandler.exists("testnode").then (exists) ->
              #check if the tstnode exists, otherwise the test is useless
              if (exists)
                ZookeeperHandler.createPathIfNotExist("testnode")
                .then ->
                  check done, ->
                    expect(true).equal(true, "should resolve")
                .catch (error) ->
                  check done, ->
                    expect(error).equal(false)
              else
                check done, ->
                  expect(true).equal(false, "(Precondition failed)")


      it "should not reject with error if path does not exist", (done) ->
        ZookeeperHandler.registerEvents()
        ZookeeperHandler.connect()
        .then ->
          ZookeeperHandler.createPathIfNotExist("testnode2")
        .then ->
          check done, ->
            expect(true).equal(true, "should resolve")
        .catch (error) ->
          check done, ->
            expect(error).equal(false)

    describe "@setData()", ->
      it "should reject if path to set data to does not exist", (done) ->
        ZookeeperHandler.registerEvents()
        ZookeeperHandler.connect()
        .then ->
          ZookeeperHandler.setData("anynotexistingnode", "test")
        .then ->
          check done, ->
            expect(true).equal(false, "should not resolve")
        .catch (error) ->
          check done, ->
            expect(true).equal(true)

    describe "@getData()", ->
      it "should reject if path to get data from does not exist", (done) ->

        ZookeeperHandler.registerEvents()
        ZookeeperHandler.connect()
        .then ->
          ZookeeperHandler.getData("anynotexistingnode")
        .then ->
          check done, ->
            expect(true).equal(false, "should not resolve")
        .catch (error) ->
          check done, ->
            expect(true).equal(true)

      it "should reject if received data is no json", (done) ->
        ZookeeperHandler.registerEvents()
        ZookeeperHandler.connect()
        .then ->
          ZookeeperHandler.createPathIfNotExist("anydata")
        .then ->
          ZookeeperHandler.client.setData ZookeeperHandler.namespace() + "/anydata",new Buffer("novalidjson{"), (error, stat) ->
            ZookeeperHandler.getData("anydata")
            .then (data)->
              check done, ->
                expect(true).equal(false, "should not resolve with " + data)
            .catch (error) ->
              check done, ->
                expect(error).equal("anydata has no valid json-data")
        .catch (error) ->
          check done, ->
            expect(error).equal(false, error + " should not have been thrown")

    describe "@createNamespace", ->
      it "should reject, if namespace could not be created", (done) ->
        ZookeeperHandler.registerEvents()
        ZookeeperHandler.connect()
        .then ->
          ZookeeperHandler.createNamespace("myfunkynamespace/ACB") #not allowed by zookeeer (missing slash)
          .then ->
            check done, ->
              expect(true).equal(false, "should not resolve")
          .catch (error) ->
            check done, ->
              expect(true).equal(true)
        .catch (error) ->
          check done, ->
            expect(true).equal(false, "error should not be thrown: " + error)


    describe "@createBaseStructure", ->
      it "should reject, if anything on creating basestructure went wrong", (done) ->
        ZookeeperHandler.registerEvents()
        ZookeeperHandler.connect()
        ZookeeperHandler.createPathIfNotExist = -> Q.reject("error")
        ZookeeperHandler.createBaseStructure()
        .then ->
          check done, ->
            expect(true).equal(false, "should not resolve")
        .catch (error) ->
          check done, ->
            expect(error).equal("error")

    xdescribe "@exists", ->
      it "should reject, if stat of path could not be checked", (done) ->
        ZookeeperHandler.registerEvents()
        ZookeeperHandler.connect()
        ZookeeperHandler.createPathIfNotExist = -> Q.reject("error")
        ZookeeperHandler.exists("a b c") #not allowed by zookeeer (blanks)
        .then ->
          check done, ->
            expect(true).equal(false, "should not resolve")
        .catch (error) ->
          check done, ->
            expect(error).equal("error")

    xdescribe "@remove", ->
      it "should reject, path could not be removed", (done) ->
        check done, ->
          expect(true).equal(false)

    xdescribe "@electMaster", ->
      it "should reject, if election failed", (done) ->
        check done, ->
          expect(true).equal(false)

    xdescribe "@getMasterId", ->
      it "should reject, if no masterid could be fetched", (done) ->
        check done, ->
          expect(true).equal(false)

    xdescribe "@registerMember", ->
      it "should reject, if anything fails", (done) ->
        check done, ->
          expect(true).equal(false)







