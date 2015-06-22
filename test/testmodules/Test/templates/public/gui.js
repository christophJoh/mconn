// Generated by CoffeeScript 1.9.1
(function() {
  this.app.config([
    '$routeProvider', function($routeProvider) {
      $routeProvider.when('/modules/Test/main', {
        templateUrl: 'modules/Test/main',
        controller: 'TestCtrl'
      });
      $routeProvider.when('/modules/Test/presets', {
        templateUrl: 'modules/Test/presets',
        controller: 'TestCtrl'
      });
      return $routeProvider.when('/modules/Test/queue', {
        templateUrl: 'modules/Test/queue',
        controller: 'TestCtrl'
      });
    }
  ]);

  this.app.controller('TestCtrl', [
    '$scope', '$rootScope', function($scope, $rootScope) {
      if (!$scope.webSocketEventsAreBinded) {
        if ($rootScope.socket) {
          $rootScope.socket.disconnect();
        }
        $rootScope.socket = window.connectToNamespace("Test", $rootScope);
        $rootScope.socket.on("updateTest", function(data) {
          return $scope.$apply(function() {
            return $scope.Testdata = data;
          });
        });
        $rootScope.socket.on("updateTestInventory", function(data) {
          return $scope.$apply(function() {
            return $scope.inventory = data;
          });
        });
        $rootScope.socket.on("updatePresets", function(data) {
          return $scope.$apply(function() {
            return $scope.presets = data;
          });
        });
        $rootScope.socket.on("updateTestQueue", function(data) {
          return $scope.$apply(function() {
            $scope.queue = data.queue;
            return $scope.queuelength = data.queuelength;
          });
        });
        return $scope.webSocketEventsAreBinded = true;
      }
    }
  ]);

}).call(this);
