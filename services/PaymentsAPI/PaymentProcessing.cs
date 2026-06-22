using FCG.Contracts;
using MassTransit;

namespace PaymentsAPI;

public sealed class PaymentProcessor(IConfiguration configuration)
{
    public PaymentProcessedEvent Process(OrderPlacedEvent order)
    {
        var forceRejected = configuration.GetValue<bool>("Payments:ForceRejected");
        var status = forceRejected ? PaymentStatuses.Rejected : PaymentStatuses.Approved;

        return new PaymentProcessedEvent(
            order.OrderId,
            order.UserId,
            order.GameId,
            order.GameTitle,
            order.Price,
            status,
            DateTime.UtcNow);
    }
}

public sealed class OrderPlacedConsumer(
    PaymentProcessor processor,
    IPublishEndpoint publisher,
    ILogger<OrderPlacedConsumer> logger) : IConsumer<OrderPlacedEvent>
{
    public async Task Consume(ConsumeContext<OrderPlacedEvent> context)
    {
        var payment = processor.Process(context.Message);
        logger.LogInformation("Pagamento {Status} processado para pedido {OrderId}.", payment.Status, payment.OrderId);
        await publisher.Publish(payment, context.CancellationToken);
    }
}
