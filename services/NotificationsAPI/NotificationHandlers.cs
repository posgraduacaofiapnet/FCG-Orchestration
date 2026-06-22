using FCG.Contracts;
using MassTransit;

namespace NotificationsAPI;

public sealed class NotificationLogService(ILogger<NotificationLogService> logger)
{
    public string SendWelcome(UserCreatedEvent message)
    {
        var text = $"E-mail de boas-vindas enviado para {message.Email}.";
        logger.LogInformation("{Message}", text);
        return text;
    }

    public string? SendPurchaseConfirmation(PaymentProcessedEvent message)
    {
        if (message.Status != PaymentStatuses.Approved)
        {
            logger.LogInformation("Pagamento rejeitado para pedido {OrderId}; nenhuma confirmacao enviada.", message.OrderId);
            return null;
        }

        var text = $"E-mail de confirmacao de compra enviado para usuario {message.UserId} sobre {message.GameTitle}.";
        logger.LogInformation("{Message}", text);
        return text;
    }
}

public sealed class UserCreatedConsumer(NotificationLogService notifications) : IConsumer<UserCreatedEvent>
{
    public Task Consume(ConsumeContext<UserCreatedEvent> context)
    {
        notifications.SendWelcome(context.Message);
        return Task.CompletedTask;
    }
}

public sealed class PaymentProcessedConsumer(NotificationLogService notifications) : IConsumer<PaymentProcessedEvent>
{
    public Task Consume(ConsumeContext<PaymentProcessedEvent> context)
    {
        notifications.SendPurchaseConfirmation(context.Message);
        return Task.CompletedTask;
    }
}
