

def testIfLibraryExists():
	from com.rabbitmq.client import ConnectionFactory
	factory = ConnectionFactory()
	logger = system.util.getLogger("infrastructure.amqp")
	logger.info("AMQP Client loaded! Class: " + factory.getClass().getName())