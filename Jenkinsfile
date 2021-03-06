#!groovy
properties(
  [
    buildDiscarder(logRotator(artifactDaysToKeepStr: '', artifactNumToKeepStr: '', daysToKeepStr: '', numToKeepStr: '100')),
    parameters(
      [
        string(name: 'CLI_REPO', defaultValue: 'docker/cli', description: 'docker/cli repo to pull from'),
        string(name: 'CLI_REV', defaultValue: 'master', description: 'Revision to base the test runs off (branch / sha1)'),
        string(name: 'ENGINE_REPO', defaultValue: 'moby/moby', description: 'moby/moby '),
        string(name: 'ENGINE_REV', defaultValue: 'master', description: 'Revision to base the test runs off (branch / sha1'),
      ]
    ),
    pipelineTriggers([cron('H 11 * * *')])
  ]
)

aws_creds = [
  $class: 'AmazonWebServicesCredentialsBinding',
  accessKeyVariable: 'AWS_ACCESS_KEY_ID',
  secretKeyVariable: 'AWS_SECRET_ACCESS_KEY',
  credentialsId: 'ci-public@docker-qa.aws'
]

def saveS3(def Map args=[:]) {
    def awscli = args.awscli ?: 'docker run --rm -e AWS_SECRET_ACCESS_KEY -e AWS_ACCESS_KEY_ID -v `pwd`:/z -w /z anigeo/awscli@sha256:669501d7b48fe5f00a3a2b23edfa1d75f43382835b0b54327a751c1bc52bf3bc'
    withCredentials([aws_creds, string(credentialsId: 'jenkins-s3-buck', variable: 'JENKINS_S3_BUCK')]) {
        sh("${awscli} s3 cp --only-show-errors '${args.name}' 's3://$JENKINS_S3_BUCK/${env.BUILD_TAG}/'")
    }
}

def readS3(def Map args=[:]) {
    def awscli = args.awscli ?: 'docker run --rm -e AWS_SECRET_ACCESS_KEY -e AWS_ACCESS_KEY_ID -v `pwd`:/z -w /z anigeo/awscli@sha256:669501d7b48fe5f00a3a2b23edfa1d75f43382835b0b54327a751c1bc52bf3bc'
    withCredentials([aws_creds, string(credentialsId: 'jenkins-s3-buck', variable: 'JENKINS_S3_BUCK')]) {
        sh("${awscli} s3 cp --only-show-errors 's3://$JENKINS_S3_BUCK/${env.BUILD_TAG}/${args.name}' .")
    }
}

def stashS3(def Map args=[:]) {
    def awscli = args.awscli ?: 'docker run --rm -e AWS_SECRET_ACCESS_KEY -e AWS_ACCESS_KEY_ID -v `pwd`:/z -w /z anigeo/awscli@sha256:669501d7b48fe5f00a3a2b23edfa1d75f43382835b0b54327a751c1bc52bf3bc'
    sh("find . -L -path './${args.includes}' | tar -c -z -f '${args.name}.tar.gz' -T -")
    withCredentials([aws_creds, string(credentialsId: 'jenkins-s3-buck', variable: 'JENKINS_S3_BUCK')]) {
        sh("${awscli} s3 cp --only-show-errors '${args.name}.tar.gz' 's3://$JENKINS_S3_BUCK/${env.BUILD_TAG}/'")
    }
    sh("rm -f '${args.name}.tar.gz'")
}

def unstashS3(def name = '', def awscli = 'docker run --rm -e AWS_SECRET_ACCESS_KEY -e AWS_ACCESS_KEY_ID -v `pwd`:/z -w /z anigeo/awscli@sha256:669501d7b48fe5f00a3a2b23edfa1d75f43382835b0b54327a751c1bc52bf3bc') {
    withCredentials([aws_creds, string(credentialsId: 'jenkins-s3-buck', variable: 'JENKINS_S3_BUCK')]) {
        sh("${awscli} s3 cp --only-show-errors 's3://$JENKINS_S3_BUCK/${env.BUILD_TAG}/${name}.tar.gz' .")
    }
    sh("tar -x -z -f '${name}.tar.gz'")
    sh("rm -f '${name}.tar.gz'")
}

def init_steps = [
  'init': { ->
    stage('src') {
      wrappedNode(label: 'aufs', cleanWorkspace: true) {
        currentBuild.displayName = "${params.ENGINE_REPO}-${params.ENGINE_REV}-${params.CLI_REPO}-${params.CLI_REV}"
        withChownWorkspace {
          checkout scm
          sh('make clean')
          sshagent(['docker-jenkins.github.ssh']) {
            dir('docker-ce/components/cli') {
              git url: "https://github.com/${params.CLI_REPO}.git"
            }
            sh("git -C docker-ce/components/cli checkout ${params.CLI_REV}")
            dir('docker-ce/components/engine') {
              git url: "https://github.com/${params.ENGINE_REPO}.git"
            }
            sh("git -C docker-ce/components/engine checkout ${params.ENGINE_REV}")
            sh('cat docker-ce/components/cli/VERSION > docker-ce/VERSION')
            sh('make docker-ce.tgz docker-gitcommit.txt docker-dev binary-daemon binary-client')
          }
          stashS3(name: 'bundles-binary-daemon', includes: 'bundles/latest/binary-daemon/**')
          stashS3(name: 'build-binary-client', includes: 'docker-ce/components/cli/build/*')
          archiveArtifacts('docker-dev-digest.txt')
          saveS3(name: 'docker-dev-digest.txt')
          saveS3(name: 'docker-gitcommit.txt')
          saveS3(name: 'docker-ce.tgz')
        }
      }
    }
  }
]

def testSuites = [
  'DockerSuite',
  'DockerAuthzSuite',
  'DockerAuthzV2Suite',
  'DockerDaemonSuite',
  'DockerExternalGraphdriverSuite',
  'DockerExternalVolumeSuite',
  'DockerHubPullSuite',
  'DockerNetworkSuite',
  'DockerRegistrySuite',
  'DockerRegistryAuthHtpasswdSuite',
  'DockerRegistryAuthTokenSuite',
  'DockerSchema1RegistrySuite',
  'DockerSwarmSuite',
  'DockerTrustSuite',
  'DockerTrustedSwarmSuite',
]

def genTestStep(String s) {
  return [ "${s}" : { ->
    stage("${s}") {
      wrappedNode(label: 'aufs', cleanWorkspace: true) {
        withChownWorkspace {
          checkout scm
          sh('make clean')
          unstashS3('bundles-binary-daemon')
          unstashS3('bundles-binary-daemon')
          unstashS3('build-binary-client')
          readS3(name: 'docker-gitcommit.txt')
          readS3(name: 'docker-dev-digest.txt')
          img = sh(script: 'cat docker-dev-digest.txt', returnStdout: true).trim()
          docker_gitcommit = sh(script: 'cat docker-gitcommit.txt', returnStdout: true).trim()
          img = sh(script: 'cat docker-dev-digest.txt', returnStdout: true).trim()
          try {
            sh("make DOCKER_GITCOMMIT=${docker_gitcommit} DOCKER_DEV_IMG=${img} TEST_SUITE=${s} test-integration-cli log-${s}.tgz")
          } finally {
            sh("make log-${s}.tgz")
            archiveArtifacts("log-${s}.tgz")
          }
        }
      }
    }
  } ]
}

def test_steps = [
  'client-unit-test': { ->
    stage('client-unit-test') {
      wrappedNode(label: 'aufs', cleanWorkspace: true) {
        withChownWorkspace {
          checkout scm
          sh('make clean')
          readS3(name: 'docker-ce.tgz')
          sh('make extract-src client-unit-test')
        }
      }
    }
  },
  'daemon-unit-test': { ->
    stage('daemon-unit-test') {
      wrappedNode(label: 'aufs', cleanWorkspace: true) {
        withChownWorkspace {
          checkout scm
          sh('make clean')
          readS3(name: 'docker-ce.tgz')
          readS3(name: 'docker-dev-digest.txt')
          sh('make extract-src daemon-unit-test')
        }
      }
    }
  },
]

for (s in testSuites) {
  test_steps << genTestStep(s)
}

parallel(init_steps)
parallel(test_steps)
