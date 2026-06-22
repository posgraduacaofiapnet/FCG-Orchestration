using FluentValidation;

namespace UsersAPI;

public sealed class RegisterUserRequestValidator : AbstractValidator<RegisterUserRequest>
{
    public RegisterUserRequestValidator()
    {
        RuleFor(request => request.Name).NotEmpty().MaximumLength(150);
        RuleFor(request => request.Email).NotEmpty().EmailAddress().MaximumLength(150);
        RuleFor(request => request.Password)
            .NotEmpty()
            .MinimumLength(PasswordPolicy.MinimumLength)
            .Must(PasswordPolicy.IsStrong)
            .WithMessage("Senha deve ter no minimo 8 caracteres, letras, numeros e caracteres especiais.");
    }
}

public sealed class LoginRequestValidator : AbstractValidator<LoginRequest>
{
    public LoginRequestValidator()
    {
        RuleFor(request => request.Email).NotEmpty().EmailAddress();
        RuleFor(request => request.Password).NotEmpty();
    }
}
