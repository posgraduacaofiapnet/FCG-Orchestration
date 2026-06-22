using FCG.Contracts;
using MassTransit;
using Microsoft.EntityFrameworkCore;

namespace UsersAPI;

public interface IUserEventPublisher
{
    Task PublishUserCreatedAsync(UserCreatedEvent message, CancellationToken cancellationToken);
}

public sealed class MassTransitUserEventPublisher(IPublishEndpoint publisher) : IUserEventPublisher
{
    public Task PublishUserCreatedAsync(UserCreatedEvent message, CancellationToken cancellationToken)
    {
        return publisher.Publish(message, cancellationToken);
    }
}

public sealed class AuthService(
    UsersDbContext dbContext,
    JwtTokenService tokenService,
    IUserEventPublisher publisher)
{
    public async Task<IResult> RegisterAsync(RegisterUserRequest request, CancellationToken cancellationToken)
    {
        if (await dbContext.Users.AnyAsync(user => user.Email == request.Email, cancellationToken))
        {
            return Results.UnprocessableEntity(new { error = "Users.EmailAlreadyRegistered" });
        }

        var user = new UserAccount
        {
            Name = request.Name,
            Email = request.Email,
            PasswordHash = PasswordHasher.Hash(request.Password),
            Role = "User",
            CreatedAt = DateTime.UtcNow
        };

        dbContext.Users.Add(user);
        await dbContext.SaveChangesAsync(cancellationToken);

        await publisher.PublishUserCreatedAsync(new UserCreatedEvent(user.Id, user.Name, user.Email, user.CreatedAt), cancellationToken);

        return Results.Created($"/api/users/{user.Id}", new { user.Id, user.Name, user.Email, user.Role });
    }

    public async Task<IResult> LoginAsync(LoginRequest request, CancellationToken cancellationToken)
    {
        var user = await dbContext.Users.FirstOrDefaultAsync(user => user.Email == request.Email, cancellationToken);
        if (user is null || !PasswordHasher.Verify(request.Password, user.PasswordHash))
        {
            return Results.Unauthorized();
        }

        return Results.Ok(new AuthResponse(tokenService.Generate(user), user.Id, user.Name, user.Email, user.Role));
    }
}
